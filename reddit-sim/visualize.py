import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys

def plot_metrics(csv_file="metrics.csv"):
    """
    Reads the 'metrics.csv' file and generates four key
    performance graphs for your report.
    """
    print(f"Loading data from '{csv_file}'...")
    
    try:
        df = pd.read_csv(
            csv_file,
            header=None,
            names=["timestamp", "metric_type", "action", "value"]
        )
    except FileNotFoundError:
        print(f"Error: '{csv_file}' not found.")
        print("Please run your Gleam simulation first to generate it.")
        sys.exit(1)
    except pd.errors.EmptyDataError:
        print(f"Error: '{csv_file}' is empty.")
        print("Did the simulation run long enough to log metrics?")
        sys.exit(1)

    df['value'] = pd.to_numeric(df['value'])

    latency_df = df[df['metric_type'] == 'latency_avg_ms'].copy()
    health_df = df[df['metric_type'] == 'health_count'].copy()
    engine_df = df[df['metric_type'] == 'engine_stat'].copy()

    print("Data loaded. Generating plots...")

    plt.figure(figsize=(12, 7))
    for action in latency_df['action'].unique():
        action_data = latency_df[latency_df['action'] == action]
        plt.plot(action_data['timestamp'], action_data['value'], label=action, marker='o', markersize=4)
    
    plt.title('Average Action Latency Over Time', fontsize=16)
    plt.xlabel('Time (seconds)', fontsize=12)
    plt.ylabel('Average Latency (ms)', fontsize=12)
    plt.legend()
    plt.grid(True, linestyle='--', alpha=0.6)
    plt.tight_layout()
    plt.savefig('plots/1_latency_over_time.png')
    print("Saved 'plots/1_latency_over_time.png'")

    plt.figure(figsize=(12, 7))
    for stat in engine_df['action'].unique():
        stat_data = engine_df[engine_df['action'] == stat]
        plt.plot(stat_data['timestamp'], stat_data['value'], label=stat, marker='o', markersize=4)
    
    plt.title('Engine State Size Over Time', fontsize=16)
    plt.xlabel('Time (seconds)', fontsize=12)
    plt.ylabel('Total Count', fontsize=12)
    plt.legend()
    plt.grid(True, linestyle='--', alpha=0.6)
    plt.tight_layout()
    plt.savefig('plots/2_system_state_size.png')
    print("Saved 'plots/2_system_state_size.png'")

    health_totals = health_df.sort_values('timestamp').groupby('action').last().reset_index()
    
    success_data = health_totals[health_totals['action'].str.contains('success')]
    failed_data = health_totals[health_totals['action'].str.contains('failed')]
    
    success_data['action_base'] = success_data['action'].str.replace('_success', '')
    failed_data['action_base'] = failed_data['action'].str.replace('_failed', '')
    
    plot_data = pd.merge(
        success_data, 
        failed_data, 
        on='action_base', 
        how='outer', 
        suffixes=('_success', '_failed')
    ).fillna(0)

    plt.figure(figsize=(14, 8))
    bar_width = 0.35
    index = np.arange(len(plot_data['action_base']))
    
    plt.bar(index, plot_data['value_success'], bar_width, label='Success', color='green')
    plt.bar(index + bar_width, plot_data['value_failed'], bar_width, label='Failed', color='red')
    
    plt.title('Total Action Health (Success vs. Failed)', fontsize=16)
    plt.xlabel('Action Type', fontsize=12)
    plt.ylabel('Total Count', fontsize=12)
    plt.xticks(index + bar_width / 2, plot_data['action_base'], rotation=45, ha='right')
    plt.legend()
    plt.grid(True, axis='y', linestyle='--', alpha=0.6)
    plt.tight_layout()
    plt.savefig('plots/3_system_health_totals.png')
    print("Saved 'plots/3_system_health_totals.png'")

    health_df = health_df.sort_values('timestamp')
    
    health_df['count_diff'] = health_df.groupby('action')['value'].diff().fillna(0)
    health_df['time_diff'] = health_df.groupby('action')['timestamp'].diff().fillna(0)
    
    health_df['throughput'] = (health_df['count_diff'] / health_df['time_diff']).replace([np.inf, -np.inf], 0).fillna(0)
    
    throughput_data = health_df[health_df['action'].str.contains('success')]
    
    plt.figure(figsize=(12, 7))
    for action in throughput_data['action'].unique():
        action_data = throughput_data[throughput_data['action'] == action]
        plt.plot(action_data['timestamp'][1:], action_data['throughput'][1:], label=action.replace('_success', ''), marker='o', markersize=4)
    
    plt.title('System Throughput (Actions/Sec)', fontsize=16)
    plt.xlabel('Time (seconds)', fontsize=12)
    plt.ylabel('Throughput (actions/sec)', fontsize=12)
    plt.legend()
    plt.grid(True, linestyle='--', alpha=0.6)
    plt.tight_layout()
    plt.savefig('plots/4_system_throughput.png')
    print("Saved 'plots/4_system_throughput.png'")

    print("\nAll plots saved as PNG files in the current directory.")
    plt.show()

if __name__ == "__main__":
    plot_metrics()
