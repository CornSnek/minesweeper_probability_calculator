from torch.utils.data import Dataset
import os
import csv
import labels
from PIL import Image

class TileData:
    path:str
    category:int
    def __init__(self, image_path, category_str):
        self.path=image_path
        self.category=labels.LABELS[category_str]
class TileDataSet(Dataset):
    data:list[TileData]
    def __init__(self, image_data_path, transform):
        self.data=[]
        self.img_path=image_data_path
        self.transform=transform
        with open(os.path.join(image_data_path,'images.csv')) as f:
            f.readline()
            csv_reader=csv.reader(f)
            for row in csv_reader:
                self.data.append(TileData(row[0].strip(),row[1].strip()))
    def __len__(self):
        return len(self.data)
    def __getitem__(self, idx):
        td:TileData=self.data[idx]
        image = Image.open(os.path.join(self.img_path,td.path)).convert("RGBA")
        new_image = Image.new("RGB", image.size, (0,0,0))
        new_image.paste(image, mask=image.split()[3])
        return (self.transform(new_image), td.category)