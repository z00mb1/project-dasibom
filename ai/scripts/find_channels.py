import sys
import os
import torch
import cv2
import dlib
import numpy as np
from PIL import Image, ImageDraw
import torchvision.transforms as transforms
from insightface.app import FaceAnalysis

sys.path.insert(0, r'C:\Users\ekzmd\Desktop\dasibom-project\plan_c\SAM')

from models.psp import pSp
from datasets.augmentations import AgeTransformer
from utils.common import tensor2im
from argparse import Namespace

MODEL_PATH = r'C:\Users\ekzmd\sam_korean_best_model.pt'
LANDMARK_PATH = r'C:\Users\ekzmd\Desktop\dasibom-project\plan_c\SAM\shape_predictor_68_face_landmarks.dat'
INPUT_IMAGE = r'C:\Users\ekzmd\Desktop\dasibom-project\dasibom-fullft\data\raw\aihub\Training\01.원천데이터\0893_1972_15_00000024_F.png'
OUTPUT_DIR = r'C:\Users\ekzmd\channel_scan10'
TARGET_AGE = 40
DELTA = 20.0
SCAN_LATENTS = [6, 7]

os.makedirs(OUTPUT_DIR, exist_ok=True)

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

def to_pil(tensor):
    result = tensor2im(tensor)
    if isinstance(result, Image.Image):
        return result
    return Image.fromarray(result)

def save_comparison(base_img, mod_img, label, path):
    combined = Image.new('RGB', (512, 280), (30, 30, 30))
    combined.paste(base_img.resize((256, 256)), (0, 0))
    combined.paste(mod_img.resize((256, 256)), (256, 0))
    draw = ImageDraw.Draw(combined)
    draw.text((10, 258), "BASE", fill=(200, 200, 200))
    draw.text((266, 258), label, fill=(255, 220, 100))
    combined.save(path)

def crop_and_align_face(image_np):
    faces = face_app.get(image_np)
    if not faces:
        raise ValueError("얼굴을 찾을 수 없습니다.")
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

img_np = cv2.imdecode(np.fromfile(INPUT_IMAGE, dtype=np.uint8), cv2.IMREAD_COLOR)
aligned_face = crop_and_align_face(img_np)
input_tensor = transform(aligned_face).unsqueeze(0).cuda()
age_transformer = AgeTransformer(target_age=TARGET_AGE)

with torch.no_grad():
    input_with_age = age_transformer(input_tensor.squeeze().cpu()).unsqueeze(0).cuda()
    result_base, codes = model(input_with_age, return_latents=True, randomize_noise=False)
    print("codes shape:", codes.shape)
    base_pil = to_pil(result_base[0])
    base_pil.save(os.path.join(OUTPUT_DIR, 'base.jpg'))
    print("기본 결과 저장 완료\n")

print(f"W space 스캔 시작 (DELTA={DELTA})...")

for latent_idx in SCAN_LATENTS:
    latent_dir = os.path.join(OUTPUT_DIR, f'latent_{latent_idx}')
    os.makedirs(latent_dir, exist_ok=True)
    print(f"latent {latent_idx} 스캔 중...")

    for dim in range(30):
        with torch.no_grad():
            codes_mod = codes.clone()
            codes_mod[:, latent_idx, dim] += DELTA
            result_mod, _ = model.decoder([codes_mod], input_is_latent=True, randomize_noise=False)
            result_mod = model.face_pool(result_mod)
            mod_pil = to_pil(result_mod[0])

        label = f"latent_{latent_idx} dim_{dim:03d} +{DELTA}"
        save_path = os.path.join(latent_dir, f'dim_{dim:03d}.jpg')
        save_comparison(base_pil, mod_pil, label, save_path)

    print(f"  → latent_{latent_idx} 완료")

print(f"\n스캔 완료! {OUTPUT_DIR} 폴더 확인해요.")