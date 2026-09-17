import sys
import os
import torch
import cv2
import dlib
import numpy as np
from PIL import Image
import torchvision.transforms as transforms
from insightface.app import FaceAnalysis
from argparse import Namespace
from tqdm import tqdm

sys.path.insert(0, r'C:\Users\ekzmd\Desktop\dasibom-project\plan_c\SAM')

from models.psp import pSp
from datasets.augmentations import AgeTransformer

MODEL_PATH = r'C:\Users\ekzmd\sam_korean_best_model.pt'
LANDMARK_PATH = r'C:\Users\ekzmd\Desktop\dasibom-project\plan_c\SAM\shape_predictor_68_face_landmarks.dat'
KOREAN_DIR = r'C:\Users\ekzmd\Desktop\dasibom-project\dasibom-fullft\data\raw\aihub\Training\01.원천데이터'
OUTPUT_PATH = r'C:\Users\ekzmd\interfacegan\korean_latents.npy'
MAX_IMAGES = 500  # 일단 500장으로 테스트

os.makedirs(r'C:\Users\ekzmd\interfacegan', exist_ok=True)

print("전처리 모델 로딩 중...")
face_app = FaceAnalysis(name='buffalo_l', providers=['CPUExecutionProvider'])
face_app.prepare(ctx_id=0, det_size=(640, 640))
face_detector = dlib.get_frontal_face_detector()
landmark_predictor = dlib.shape_predictor(LANDMARK_PATH)

print("SAM 모델 로딩 중...")
ckpt = torch.load(MODEL_PATH, map_location='cpu')
opts = ckpt['opts']
opts['checkpoint_path'] = MODEL_PATH
opts['device'] = 'cuda'
opts = Namespace(**opts)
model = pSp(opts)
model.eval()
model.cuda()
print("로딩 완료!")

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

transform = transforms.Compose([
    transforms.Resize((256, 256)),
    transforms.ToTensor(),
    transforms.Normalize([0.5, 0.5, 0.5], [0.5, 0.5, 0.5])
])

age_transformer = AgeTransformer(target_age=30)

image_files = [f for f in os.listdir(KOREAN_DIR) if f.endswith('.png') or f.endswith('.jpg')]
image_files = image_files[:MAX_IMAGES]

latent_codes = []
success = 0
fail = 0

for fname in tqdm(image_files):
    try:
        fpath = os.path.join(KOREAN_DIR, fname)
        img_np = cv2.imdecode(np.fromfile(fpath, dtype=np.uint8), cv2.IMREAD_COLOR)
        aligned = crop_and_align_face(img_np)
        if aligned is None:
            fail += 1
            continue

        input_tensor = transform(aligned).unsqueeze(0).cuda()
        with torch.no_grad():
            input_with_age = age_transformer(input_tensor.squeeze().cpu()).unsqueeze(0).cuda()
            _, codes = model(input_with_age, return_latents=True, randomize_noise=False)
            latent_codes.append(codes.squeeze().cpu().numpy())
        success += 1

    except Exception as e:
        fail += 1
        continue

latent_array = np.array(latent_codes)
np.save(OUTPUT_PATH, latent_array)
print(f"\n완료! 성공: {success}, 실패: {fail}")
print(f"저장: {OUTPUT_PATH}")
print(f"shape: {latent_array.shape}")