# -*- coding: utf-8 -*-
import sys
import os

SAM_ROOT = '/root/SAM'
sys.path.insert(0, SAM_ROOT)

import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
import cv2
import dlib
import numpy as np
from PIL import Image
import torchvision.transforms as transforms
import torchvision.models as torchvision_models
from torch.utils.data import Dataset, DataLoader
from insightface.app import FaceAnalysis
from argparse import Namespace
import traceback
import time

from models.psp import pSp
from datasets.augmentations import AgeTransformer
from criteria.lpips.lpips import LPIPS

# ===================== 설정 =====================
MODEL_PATH = '/root/models/sam_korean_best_model.pt'
LANDMARK_PATH = '/root/SAM/shape_predictor_68_face_landmarks.dat'
DATA_DIR = '/data/aihub/Training/01.원천데이터'
DATA_DIR_528 = '/root/aihub/individuals_528'  # AIHub 528 추가 데이터
SAVE_DIR = '/root/ragan_checkpoints_v3'
FAIRFACE_PATH = '/root/models/res34_fair_align_multi_7_20190809.pt'

BATCH_SIZE = 4
NUM_WORKERS = 4
LOG_INTERVAL = 100
SAVE_INTERVAL = 1000
MAX_STEPS = 50000
LR = 1e-4
TARGET_AGE = 40

# FairFace 인종 클래스
EAST_ASIAN_IDX = 3
SOUTHEAST_ASIAN_IDX = 4
RACE_LOSS_WEIGHT = 1.0  # v3: Race loss 가중치 0.5→1.0으로 강화

print("스크립트 시작")
os.makedirs(SAVE_DIR, exist_ok=True)

# ===================== 전처리 모델 =====================
print("전처리 모델 로딩 중...")
face_app = FaceAnalysis(name='buffalo_l', providers=['CUDAExecutionProvider'])
face_app.prepare(ctx_id=0, det_size=(640, 640))
face_detector = dlib.get_frontal_face_detector()
landmark_predictor = dlib.shape_predictor(LANDMARK_PATH)

def crop_and_align_face(image_np):
    faces = face_app.get(image_np)
    if not faces:
        return None
    face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0]) * (f.bbox[3]-f.bbox[1]))
    x1, y1, x2, y2 = [int(v) for v in face.bbox]
    w, h = x2-x1, y2-y1
    pad = int(max(w, h) * 0.4)
    x1 = max(0, x1-pad)
    y1 = max(0, y1-pad)
    x2 = min(image_np.shape[1], x2+pad)
    y2 = min(image_np.shape[0], y2+pad)
    cropped = image_np[y1:y2, x1:x2]
    cropped = cv2.resize(cropped, (256, 256))
    rgb = cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB)
    dets = face_detector(rgb, 1)
    if not dets:
        return Image.fromarray(rgb)
    shape = landmark_predictor(rgb, dets[0])
    landmarks = np.array([[shape.part(i).x, shape.part(i).y] for i in range(68)])
    left_eye = landmarks[36:42].mean(axis=0)
    right_eye = landmarks[42:48].mean(axis=0)
    angle = np.degrees(np.arctan2(right_eye[1]-left_eye[1], right_eye[0]-left_eye[0]))
    center = tuple(map(int, ((left_eye+right_eye)/2)))
    M = cv2.getRotationMatrix2D(center, angle, 1.0)
    aligned = cv2.warpAffine(rgb, M, (256, 256))
    return Image.fromarray(aligned)

# ===================== 전처리 캐시 =====================
CACHE_DIR = os.path.join(SAVE_DIR, 'preprocessed_cache')
os.makedirs(CACHE_DIR, exist_ok=True)

def preprocess_and_cache():
    # 두 데이터 폴더 합치기
    image_files = []
    for data_dir in [DATA_DIR, DATA_DIR_528]:
        if os.path.exists(data_dir):
            files = [os.path.join(data_dir, f) for f in os.listdir(data_dir)
                     if f.lower().endswith(('.png', '.jpg'))]
            image_files.extend(files)
            print(f"  {data_dir}: {len(files)}장")

    cached_files = []
    print(f"전처리 시작: 총 {len(image_files)}장")

    for i, fpath in enumerate(image_files):
        fname = os.path.basename(fpath)
        cache_path = os.path.join(CACHE_DIR, fname.replace('.jpg', '.png').replace('.JPG', '.png'))
        if os.path.exists(cache_path):
            cached_files.append(cache_path)
            continue
        try:
            img_np = cv2.imdecode(np.fromfile(fpath, dtype=np.uint8), cv2.IMREAD_COLOR)
            aligned = crop_and_align_face(img_np)
            if aligned is None:
                continue
            aligned.save(cache_path)
            cached_files.append(cache_path)
        except Exception:
            continue
        if (i+1) % 1000 == 0:
            print(f"  전처리 진행: {i+1}/{len(image_files)}")

    print(f"전처리 완료: {len(cached_files)}장 캐시됨")
    return cached_files

# ===================== Dataset =====================
class AihubFaceDataset(Dataset):
    def __init__(self, file_list, target_age):
        self.file_list = file_list
        self.transform = transforms.Compose([
            transforms.Resize((256, 256)),
            transforms.ToTensor(),
            transforms.Normalize([0.5, 0.5, 0.5], [0.5, 0.5, 0.5])
        ])
        self.age_transformer = AgeTransformer(target_age=target_age)

    def __len__(self):
        return len(self.file_list)

    def __getitem__(self, idx):
        img = Image.open(self.file_list[idx]).convert('RGB')
        real = self.transform(img)
        input_with_age = self.age_transformer(real)
        return input_with_age, real

# ===================== SAM + RA-GAN 모델 =====================
print("SAM + RA-GAN 모델 로딩 중...")
ckpt = torch.load(MODEL_PATH, map_location='cpu')
opts = ckpt['opts']
opts['checkpoint_path'] = MODEL_PATH
opts['device'] = 'cuda'
opts = Namespace(**opts)
model = pSp(opts)
model.cuda()

model.decoder.eval()
model.encoder.eval()
model.pretrained_encoder.eval()
model.race_net.eval()
model.race_mixers.train()

# gradient 완전 차단
for param in model.decoder.parameters():
    param.requires_grad = False
for param in model.encoder.parameters():
    param.requires_grad = False
for param in model.pretrained_encoder.parameters():
    param.requires_grad = False
for param in model.race_net.parameters():
    param.requires_grad = False

trainable_params = list(model.race_mixers.parameters())
optimizer = optim.Adam(trainable_params, lr=LR)
lpips_loss = LPIPS(net_type='alex').cuda().eval()
l2_loss = nn.MSELoss()
ce_loss = nn.CrossEntropyLoss()

# ===================== FairFace 모델 =====================
print("FairFace 모델 로딩 중...")
fairface = torchvision_models.resnet34(pretrained=False)
fairface.fc = nn.Linear(512, 18)  # FairFace 출력: 7(race)+2(gender)+9(age)
fairface.load_state_dict(torch.load(FAIRFACE_PATH, map_location='cpu'))
fairface = fairface.cuda().eval()
for param in fairface.parameters():
    param.requires_grad = False

# FairFace 전처리
fairface_transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])
])

print(f"학습 파라미터 수: {sum(p.numel() for p in trainable_params):,}")

# ===================== 전처리 캐시 실행 =====================
cached_files = preprocess_and_cache()

if len(cached_files) == 0:
    print("ERROR: 캐시된 파일이 없습니다. 데이터 경로를 확인하세요.")
    sys.exit(1)

dataset = AihubFaceDataset(cached_files, TARGET_AGE)
dataloader = DataLoader(
    dataset,
    batch_size=BATCH_SIZE,
    shuffle=True,
    num_workers=NUM_WORKERS,
    pin_memory=True,
    drop_last=True
)
print(f"DataLoader 준비 완료: {len(dataset)}장, batch_size={BATCH_SIZE}")

# ===================== 학습 루프 =====================
print(f"학습 시작 (MAX_STEPS={MAX_STEPS})...")
step = 0
start_time = time.time()

while step < MAX_STEPS:
    for input_with_age, real in dataloader:
        if step >= MAX_STEPS:
            break

        input_with_age = input_with_age.cuda()
        real = real.cuda()

        optimizer.zero_grad()
        output = model(input_with_age)

        # 크기 불일치 방지
        if output.shape != real.shape:
            output = F.interpolate(output, size=(256, 256), mode='bilinear', align_corners=False)

        # output detach해서 decoder gradient 차단
        output_detached = output.detach()
        loss_l2 = l2_loss(output_detached, real)
        loss_lpips = lpips_loss(output_detached, real.detach()).mean()

        # race_mixers gradient를 위한 codes regularization loss
        with torch.no_grad():
            codes = model.encoder(input_with_age)
            if model.opts.start_from_encoded_w_plus:
                encoded_latents = model.pretrained_encoder(input_with_age[:, :-1, :, :])
                encoded_latents = encoded_latents + model.latent_avg
                codes = codes + encoded_latents
        race_codes = model.race_net(input_with_age)
        mixed_codes = model.race_mixers(codes, race_codes)
        loss_reg = l2_loss(mixed_codes, codes.detach())

        # FairFace race loss - 동양인(East Asian) 확률 높이기
        # output을 [0,1]로 변환 후 FairFace 입력 형식으로 변환
        output_01 = (output_detached * 0.5 + 0.5).clamp(0, 1)
        output_ff = fairface_transform(output_01)
        race_logits = fairface(output_ff)[:, :7]  # 첫 7개가 race
        # East Asian(3) + Southeast Asian(4) 확률 최대화
        asian_target = torch.tensor([EAST_ASIAN_IDX] * output_ff.shape[0]).cuda()
        loss_race = ce_loss(race_logits, asian_target)

        loss = loss_l2 + 0.8 * loss_lpips + 0.1 * loss_reg + RACE_LOSS_WEIGHT * loss_race

        loss.backward()
        optimizer.step()

        step += 1

        if step % LOG_INTERVAL == 0:
            elapsed = time.time() - start_time
            steps_per_sec = step / elapsed
            eta = (MAX_STEPS - step) / steps_per_sec / 3600
            print(f"Step {step}/{MAX_STEPS} | L2: {loss_l2.item():.4f} | LPIPS: {loss_lpips.item():.4f} | Reg: {loss_reg.item():.4f} | Race: {loss_race.item():.4f} | Total: {loss.item():.4f} | ETA: {eta:.1f}h")

        if step % SAVE_INTERVAL == 0:
            save_path = os.path.join(SAVE_DIR, f'ragan_step{step}.pt')
            torch.save({
                'step': step,
                'race_mixers': model.race_mixers.state_dict(),
                'optimizer': optimizer.state_dict(),
            }, save_path)
            print(f"체크포인트 저장: {save_path}")

print("학습 완료!")
final_path = os.path.join(SAVE_DIR, 'ragan_final.pt')
torch.save({
    'step': step,
    'race_mixers': model.race_mixers.state_dict(),
}, final_path)
print(f"최종 모델 저장: {final_path}")