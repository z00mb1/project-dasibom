# dasibomapp/services/kobert/train.py

import torch
from torch import nn
from torch.utils.data import DataLoader
from torch.optim import AdamW
from transformers import AutoTokenizer
from pathlib import Path
from tqdm import tqdm   # ✅ 추가

from .dataset import KoBERTDataset
from .model import KoBERTClassifier


def train():
    print("🔥 RUNNING TRAIN.PY FROM:", __file__)

    # -------------------------------------------------
    # 1️⃣ 경로 설정
    # -------------------------------------------------
    BASE_DIR = Path(__file__).resolve().parents[2]   # dasibomapp/
    DATA_PATH = BASE_DIR / "data" / "kobert_train.jsonl"
    MODEL_DIR = BASE_DIR.parent / "models"           # dasibom/models/
    MODEL_DIR.mkdir(exist_ok=True)

    print("📂 DATA PATH:", DATA_PATH)
    print("📦 MODEL DIR:", MODEL_DIR)

    # -------------------------------------------------
    # 2️⃣ Tokenizer
    # -------------------------------------------------
    tokenizer = AutoTokenizer.from_pretrained(
        "monologg/kobert",
        trust_remote_code=True
    )

    # -------------------------------------------------
    # 3️⃣ Dataset / DataLoader
    # -------------------------------------------------
    dataset = KoBERTDataset(DATA_PATH, tokenizer)
    print(f"📊 Loaded rows: {len(dataset)}")

    if len(dataset) == 0:
        raise RuntimeError("❌ KoBERT 학습 데이터가 0개입니다.")

    loader = DataLoader(
        dataset,
        batch_size=8,
        shuffle=True
    )

    # -------------------------------------------------
    # 4️⃣ Model / Optimizer / Loss
    # -------------------------------------------------
    model = KoBERTClassifier()
    optimizer = AdamW(model.parameters(), lr=2e-5)
    criterion = nn.BCEWithLogitsLoss()

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)

    # -------------------------------------------------
    # 5️⃣ Training
    # -------------------------------------------------
    model.train()
    EPOCHS = 3

    print("🚀 START TRAIN LOOP")

    for epoch in range(EPOCHS):
        total_loss = 0.0

        print(f"\n📘 Epoch {epoch + 1}/{EPOCHS}")

        progress_bar = tqdm(
            loader,
            desc=f"Epoch {epoch + 1}",
            total=len(loader),
            ncols=100
        )

        for batch in progress_bar:
            input_ids = batch["input_ids"].to(device)
            attention_mask = batch["attention_mask"].to(device)
            labels = batch["labels"].to(device)

            optimizer.zero_grad()
            logits = model(input_ids, attention_mask)
            loss = criterion(logits, labels)

            loss.backward()
            optimizer.step()

            total_loss += loss.item()

            # tqdm 우측에 loss 표시
            progress_bar.set_postfix(loss=f"{loss.item():.4f}")

        avg_loss = total_loss / len(loader)
        print(f"✅ Epoch {epoch + 1} DONE | avg loss = {avg_loss:.4f}")

    # -------------------------------------------------
    # 6️⃣ Save model
    # -------------------------------------------------
    model_path = MODEL_DIR / "kobert_cls.pt"
    torch.save(model.state_dict(), model_path)

    print(f"\n🎉 KoBERT model saved to: {model_path}")


if __name__ == "__main__":
    train()
