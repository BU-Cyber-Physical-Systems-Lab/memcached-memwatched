#!/usr/bin/env python3

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns
import numpy as np

sns.set_theme(style="whitegrid")


def plot_latencies(input_path: Path, output_path: Path | None, output_name: str):
    # Read whitespace-separated file with two columns:
    # timestamp_seconds latency_milliseconds
    df = pd.read_csv(
        input_path / (output_name + ".log"),
        sep=" ",
        header=None,
        names=["timestamp", "latency_ms"],
    )
    df=df.sort_values(by=["timestamp"]).reset_index()
    print(df["latency_ms"].max())
    print(df.head())

    sns.lineplot(
        data=df,
        x="timestamp",
        y="latency_ms",
        errorbar=None,
    )

    migration_filename=input_path / "migration_timestamp.log"
    mutilate_start_filename=input_path / "mutilate_start.log"
    if migration_filename.exists() and mutilate_start_filename.exists():
        migrations = np.loadtxt(migration_filename, dtype=np.float64)
        # Handle the case where the file contains only one timestamp
        migrations = np.atleast_1d(migrations)
        mutilate_start_file=open(mutilate_start_filename,"r")
        mutilate_start_time = mutilate_start_file.read()
        mutilate_start_file.close()
        for migration_time in migrations:
            print(f"Migration at {migration_time}s (offset {float(migration_time) - float(mutilate_start_time)})")
            plt.axvline(
                x=float(migration_time) - float(mutilate_start_time),
                color="red",
                linestyle="--",
                linewidth=0.5,
            )

    plt.ylim((0,150000))
    plt.xlabel("Timestamp from application start (s)")
    plt.ylabel("Request latency (us)")
    plt.title(f"{input_path.stem}")

    plt.tight_layout()
    plt.savefig(f"{output_path}/{output_name}.pdf")
    plt.close()

    sns.violinplot(
        x=df["latency_ms"],
    )
    plt.xlabel("Timestamp from application start, seconds")
    plt.ylabel("Request latency, useconds")
    plt.title(f"{input_path.stem}")

    plt.tight_layout()
    plt.savefig(f"{output_path}/{output_name}-dist.pdf")
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
        nargs="?",
        default="plot.pdf",
    )

    args = parser.parse_args()
    file = Path(f"{args.input_file}")

    if file.is_dir():
        for item in file.iterdir():
            if item.is_dir():
                print(f"Plotting {item.name}")
                plot_latencies(
                    item.resolve(),
                    item.resolve(),
                    f"{item.name}"
                )
    else:
        print(f"Plotting {file.name}")
        plot_latencies(file, file.parent.resolve(), args.output_file)


if __name__ == "__main__":
    main()
