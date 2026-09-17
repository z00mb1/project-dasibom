import numpy as np

KOREAN_PATH = r'C:\Users\ekzmd\interfacegan\korean_latents.npy'
WESTERN_PATH = r'C:\Users\ekzmd\interfacegan\western_latents.npy'
OUTPUT_PATH = r'C:\Users\ekzmd\interfacegan\asian_direction.npy'

korean = np.load(KOREAN_PATH)  # (495, 18, 512)
western = np.load(WESTERN_PATH)  # (500, 18, 512)

print(f"한국인 latents: {korean.shape}")
print(f"서양인 latents: {western.shape}")

# 각 그룹 평균 계산
korean_mean = korean.mean(axis=0)   # (18, 512)
western_mean = western.mean(axis=0) # (18, 512)

# 동양인 방향 벡터 = 한국인 평균 - 서양인 평균
direction = korean_mean - western_mean  # (18, 512)

# 정규화
direction_norm = direction / (np.linalg.norm(direction, axis=-1, keepdims=True) + 1e-8)

np.save(OUTPUT_PATH, direction_norm)
print(f"\n방향 벡터 저장 완료: {OUTPUT_PATH}")
print(f"shape: {direction_norm.shape}")
print(f"norm 확인 (각 latent): {np.linalg.norm(direction_norm, axis=-1)}")