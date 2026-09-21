#!/usr/bin/env python3

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

sns.set_theme(style="whitegrid")


def plot_latencies(input_path: Path, output_path: Path | None, output_name: str,global_ylim:float):
    # Read whitespace-separated file with two columns:
    # timestamp_seconds latency_milliseconds
    df = pd.read_csv(
        input_path / (output_name + ".log"),
        sep=" ",
        header=None,
        names=["timestamp", "latency_us"],
        dtype=np.float64,
    )
    df = df[df["timestamp"] > 3]
    df = df.sort_values(by=["timestamp"]).reset_index()
    print(f"BEFORE MEAN: num samples: {df[df.columns[0]].count()} worst latency: \n{df[df['latency_us'] == df['latency_us'].max()]}")
    df["timestamp"]=df["timestamp"].apply(lambda x: float(f"{x:.3f}"))
    df=df.groupby(["timestamp"]).mean().reset_index()
    last_request = df["timestamp"].iloc[-1]
    print(f"AFTER MEAN: num samples: {df[df.columns[0]].count()} worst latency: \n{df[df['latency_us'] == df['latency_us'].max()]}")
    print(df.head())

    sns.lineplot(data=df, x="timestamp", y="latency_us")

    migration_filename = input_path / "migration_timestamp.log"
    mutilate_start_filename = input_path / "mutilate_start.log"
    if migration_filename.exists() and mutilate_start_filename.exists():
        migrations = np.loadtxt(migration_filename, dtype=np.float64)
        # Handle the case where the file contains only one timestamp
        migrations = np.atleast_1d(migrations)
        mutilate_start_file = open(mutilate_start_filename, "r")
        mutilate_start_time = float(mutilate_start_file.read())
        mutilate_start_file.close()
        for migration_time in migrations:
            migration_offset = migration_time - mutilate_start_time
            print(
                f"Migration at {migration_time}s, mutilate start  at {mutilate_start_time}s (offset {migration_offset}) last request {last_request}"
            )
            if migration_offset < last_request:
                plt.axvline(
                    x=migration_offset,
                    color="red",
                    linestyle="--",
                    linewidth=0.75,
                )
    plt.ylim(top=global_ylim)
    plt.xlabel("Timestamp from application start (s)")
    plt.ylabel(r"Request latency ($\mu$s)")
    plt.title(f"{input_path.stem}")

    plt.tight_layout()
    plt.savefig(f"{output_path}/{output_name}.pdf")
    plt.close()

    sns.violinplot(
        x=df["latency_us"],
    )
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

    global_ylim:float=0
    for item in file.iterdir():
        if item.is_dir():
            df = pd.read_csv(
                item.resolve()/f"{item.name}.log",
                sep=" ",
                header=None,
                names=["timestamp", "latency_us"],
                dtype=np.float64,
            )
            df = df[df["timestamp"] > 3]
            df["timestamp"]=df["timestamp"].apply(lambda x: float(f"{x:.3f}"))
            df=df.groupby(["timestamp"]).mean().reset_index()
            print(f"{item}.log max: {df["latency_us"].max()} ")
            global_ylim= max(df["latency_us"].max()*1.05, global_ylim)
        else:
            df = pd.read_csv(
                file.resolve() /f"{file.resolve()}.log",
                sep=" ",
                header=None,
                names=["timestamp", "latency_us"],
                dtype=np.float64,
            )
            print(f"{file}.log max: {df["latency_us"].max()} ")
            global_ylim= max(df["latency_us"].max(), global_ylim)

    print(f"global y limit: {global_ylim}")
    for item in file.iterdir():
        if item.is_dir():
            print(f"Plotting {item.name}")
            plot_latencies(item.resolve(), item.resolve(), f"{item.name}",global_ylim)
        else:
            print(f"Plotting {file}")
            plot_latencies(file.resolve(), file.resolve(), f"{file.name}",global_ylim)
            break


if __name__ == "__main__":
    main()
