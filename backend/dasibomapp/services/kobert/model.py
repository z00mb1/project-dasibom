import torch.nn as nn
from transformers import BertModel

class KoBERTClassifier(nn.Module):
    def __init__(self, model_name="monologg/kobert"):
        super().__init__()
        self.bert = BertModel.from_pretrained(model_name)
        self.classifier = nn.Linear(
            self.bert.config.hidden_size,
            3  # health, behavior, risk_context
        )

    def forward(self, input_ids, attention_mask):
        outputs = self.bert(
            input_ids=input_ids,
            attention_mask=attention_mask
        )
        pooled = outputs.pooler_output
        return self.classifier(pooled)
