import torch.nn
import labels
class CNNClassifier(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.features = torch.nn.Sequential(
            torch.nn.Conv2d(1, 16, kernel_size=3, padding=1),   # [1,16,16] -> [16,16,16]
            torch.nn.BatchNorm2d(16),
            torch.nn.ReLU(),

            torch.nn.Conv2d(16, 32, kernel_size=3, padding=1),  # [16,32,32] -> [32,32,32]
            torch.nn.BatchNorm2d(32),
            torch.nn.ReLU(),
            torch.nn.MaxPool2d(2),                              # -> [32,16,16]

            torch.nn.Conv2d(32, 64, kernel_size=3, padding=1),  # -> [64,16,16]
            torch.nn.BatchNorm2d(64),
            torch.nn.ReLU(),
            torch.nn.MaxPool2d(2),                              # -> [64,8,8]

            torch.nn.Conv2d(64, 128, kernel_size=3, padding=1), # -> [128,8,8]
            torch.nn.BatchNorm2d(128),
            torch.nn.ReLU(),
            torch.nn.MaxPool2d(2),                              # -> [128,4,4]
        )

        self.classifier = torch.nn.Sequential(
            torch.nn.Flatten(),         # -> [128 * 4 * 4 = 2048]
            torch.nn.Dropout(0.125),
            torch.nn.Linear(128 * 4 * 4, 128),
            torch.nn.ReLU(),
            torch.nn.Linear(128, len(labels.LABELS))
        )
    def forward(self, x):
        x = self.features(x)
        return self.classifier(x)

