import json
import torch
from torch.utils.data import Dataset
from pathlib import Path


class KoBERTDataset(Dataset):
    def __init__(self, path, tokenizer, max_len=256):
        path = Path(path)
        self.data = [json.loads(l) for l in path.open(encoding="utf-8")]
        print("Loaded rows:", len(self.data))
        self.tokenizer = tokenizer
        self.max_len = max_len

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        row = self.data[idx]

        enc = self.tokenizer(
            row["text"],
            truncation=True,
            padding="max_length",
            max_length=self.max_len,
            return_tensors="pt"
        )

        return {
            "input_ids": enc["input_ids"].squeeze(0),
            "attention_mask": enc["attention_mask"].squeeze(0),
            "labels": torch.tensor(row["labels"], dtype=torch.float)
        }
