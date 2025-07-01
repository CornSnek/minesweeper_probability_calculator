import torch
import torch.onnx
import cnn
import argparse

def export(model_path, onnx_path):
    model = cnn.CNNClassifier()
    model.load_state_dict(torch.load(model_path, map_location='cpu'))
    model.eval()
    dummy_input = torch.randn(1,1,32,32)
    torch.onnx.export(
        model,
        dummy_input,
        onnx_path,
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
        opset_version=11
    )

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Export PyTorch model to ONNX")
    parser.add_argument("--model", required=True, help="Path to the .pth model file")
    parser.add_argument("--output", default="model.onnx", help="Path to save the .onnx file")
    args = parser.parse_args()
    export(args.model, args.output)