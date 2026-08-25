#!/usr/bin/env python3

import argparse
import pandas as pd
from pathlib import Path
import seaborn as sns
from tqdm import tqdm
import matplotlib.pyplot as plt

sns.set_theme(style="whitegrid")

def plot_latencies(input_path: Path, output_path: str):
    # Read whitespace-separated file with two columns:
    # timestamp_seconds latency_milliseconds
    df = pd.read_csv(
        input_path,
        sep=" ",
        header=None,
        names=["timestamp", "latency_ms"],
    )


    sns.lineplot(
        data=df,
        x="timestamp",
        y="latency_ms",
        errorbar=None,
    )

    plt.xlabel("Timestamp from application start, seconds")
    plt.ylabel("Request latency, milliseconds")
    plt.title(f"{input_path.stem}")

    plt.tight_layout()
    plt.savefig(output_path)
    plt.close()


def main():
    parser = argparse.ArgumentParser(
        description="Plot request latencies from a whitespace-separated data file."
    )

    parser.add_argument(
        "input_file",
        help="Path to input data file",
    )

    parser.add_argument(
        "output_file",
        help="Path to output plot file, for example plot.png",
        nargs='?',
        default="plot.pdf"
    )
    
    args = parser.parse_args()
    file=Path(f"{args.input_file}")
    if file.is_dir():
        for item in file.iterdir():
            if item.is_dir():
                print(f"Plotting {item.name}")
                plot_latencies(item.resolve()/f"{item.name}.log", f"{item.resolve()}/{item.name}.pdf")
    else:
        print(f"Plotting {file.name}")
        plot_latencies(file, args.output_file)


if __name__ == "__main__":
    main()
