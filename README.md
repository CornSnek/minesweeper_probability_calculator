# Minesweeper Probability Calculator
Web application that calculates the probability of a tile being a mine for the game Minesweeper

## GitHub Page
The web application is deployed at https://cornsnek.github.io/minesweeper_probability_calculator/

## About
I started to play Minesweeper, and I was interested in how Minesweeper Patterns are calculated as a safe number or a mine tile.
This app was created in order to calculate the mine probabilities.

## Zig Build
This project currently uses Zig 0.14.0 to build the project.

In order to build the website and/or the wasm binary: `zig build wasm -Doptimize=...`

Python 3 is also used to build the server to build and test the website: `zig build server`

## Projects Used
- **KaTeX** (https://katex.org) was added to this project to show and format the matrices and probability calculations
- **coi-serviceworker** (https://github.com/gzuidhof/coi-serviceworker) was added to this project to enable COOP and COEP headers for Github Pages


## TODO
- Fix rename row/column elements as I confused both of them as the other.