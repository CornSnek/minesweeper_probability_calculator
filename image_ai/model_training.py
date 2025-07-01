from tile_data import TileDataSet
from torchvision import transforms
import torch.nn
from torch.utils.data import DataLoader, random_split
import torch.optim

random_transforms = transforms.Compose([
    transforms.Resize((32,32)),
    transforms.ColorJitter(brightness=0.125, contrast=0.125, saturation=0.125, hue=0.125),
    transforms.RandomInvert(),
    transforms.RandomAffine(degrees=0,translate=(0.125,0.125)),
    transforms.Grayscale(),
    transforms.ToTensor(),
    transforms.Normalize([0.5], [0.5]),
])

import cnn
model = cnn.CNNClassifier()
optimizer = torch.optim.SGD(model.parameters(), lr=0.01, momentum=0.9, weight_decay=1e-5, nesterov=True)
scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
    optimizer,
    mode='min',
    factor=31/32,
    patience=3,
)
criterion = torch.nn.CrossEntropyLoss()
dataset = TileDataSet('image_data', random_transforms)
train_size = int(0.8 * len(dataset))
val_size = len(dataset) - train_size
train_dataset, val_dataset = random_split(dataset, [train_size, val_size])
train_loader = DataLoader(train_dataset, batch_size=32, shuffle=True)
val_loader = DataLoader(val_dataset, batch_size=32)

epoch=-1
cooldown_save=0
max_accuracy_now = 0.7
while True:
    epoch+=1
    if cooldown_save!=0:
        cooldown_save-=1
    else:
        max_accuracy_now = 0.7
    model.train()
    train_loss = 0
    for inputs, categories in train_loader:
        outputs = model(inputs)
        loss = criterion(outputs, categories)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        train_loss += loss.item()
    avg_train_loss = train_loss / len(train_loader)
    model.eval()
    val_loss = 0.0
    val_correct = 0
    val_total = 0
    with torch.no_grad():
        for inputs, categories in val_loader:
            outputs = model(inputs)
            loss = criterion(outputs, categories)
            val_loss += loss.item()
            preds = outputs.argmax(dim=1)
            val_correct += (preds==categories).sum().item()
            val_total += categories.size(0)
    avg_val_loss = val_loss / len(val_loader)
    val_accuracy = val_correct/val_total
    print(f"Epoch {epoch+1}, Loss: {train_loss:.4f}  Train Loss: {avg_train_loss:.4f}  Val Loss: {avg_val_loss:.4f} Accuracy: {val_accuracy:.2%}")
    if val_accuracy>max_accuracy_now:
        max_accuracy_now=val_accuracy
        torch.save(model.state_dict(), f"pth/model_a{val_accuracy:.5f}_e{epoch+1}_l{train_loss:.2f}_avl{(avg_val_loss):.2f}.pth")
        cooldown_save=100
    scheduler.step(val_loss)

