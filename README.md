# Minesweeper Probability Calculator
Web application that calculates the probability of a tile being a mine for the game Minesweeper

## GitHub Page
The web application is deployed at https://cornsnek.github.io/minesweeper_probability_calculator/

## About
I started to play Minesweeper, and I was interested in how Minesweeper Patterns are calculated as a safe number or a mine tile.
This app was created in order to calculate the mine probabilities and understand the mathematics in calculating them.

## Zig Build
This project currently uses Zig 0.14.0 to build the project.

In order to build the website and/or the wasm binary: `zig build wasm -Doptimize=...`

Python 3 is also used to build the server to build and test the website: `zig build server`

## Screenshot Detection
This program uses a neural network using **ONNX Runtime** to try to estimate and predict tiles in minesweeper screenshots. It uses python venv to set using `image_ai/requirements.txt`. To set up the neural network model training, an `image_ai/image_data` and `image_ai/image_data/images.csv` is required, where labels.csv is formatted as `filename` and `label`. Here is an example of an `images.csv` file.
```
filename, label
unknown_0.png, unknown
unknown_1.png, unknown
unknown_2.png, unknown
unknown_5.png, unknown
unknown_6.png, unknown
unknown_7.png, unknown
TileUnknown.png, unknown
...
mine_0.png, mine
flag_2.png, flag
0_1.png, 0
0_2.png, 0
0_3.png, 0
1_3.png, 1
1_5.png, 1
1_6.png, 1
...
```
`filename` is the relative path of the training image data, while the `labels` are based on the Zig MsType enum names at `src/minesweeper`. The only label/enum that is not used is `donotcare`.

The python scripts are then used to create the neural network models to detect tiles and to export the model as an `.onnx` file.
The file is then placed into the `www` folder to be used by ONNX Runtime.

## Projects Used
- **KaTeX** (https://katex.org) was added to this project to show and format the matrices and probability calculations
- **coi-serviceworker** (https://github.com/gzuidhof/coi-serviceworker) was added to this project to enable COOP and COEP headers for Github Pages
- **ONNX Runtime** (https://onnxruntime.ai) was added to this project to help detect most of the tiles in a screenshot
