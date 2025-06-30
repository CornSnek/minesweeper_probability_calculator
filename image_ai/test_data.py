from tile_data import TileDataSet
from torchvision import transforms
import torch
import cnn
use_transform = transforms.Compose([
    transforms.Resize((16,16), interpolation=transforms.InterpolationMode.NEAREST),
    transforms.Grayscale(),
    transforms.ToTensor(),
    transforms.Normalize([0.5], [0.5]),
])
#This just test the same data that was used to train. There is not a lot of minesweeper tiles to train and use for prediction analysis.
def test_dataset():
    dataset = TileDataSet('image_data', use_transform)
    model = cnn.CNNClassifier()
    model.load_state_dict(torch.load('pth/model_a0.90476_e2226_l1.43_avl1.18.pth',map_location='cpu'))
    model.eval()
    arr_results=[]
    for i in range(len(dataset)):
        (img, true_category) = dataset[i]
        tensor=img.unsqueeze(0)
        with torch.no_grad():
            output = model(tensor)
            predicted = torch.argmax(output, dim=1).item()
            arr_results.append((predicted,true_category,dataset.data[i].path))
    for (p,t,d) in arr_results:
        print(f'Pred: {p} True: {t} Image: {d}')
if __name__=='__main__':
    test_dataset()