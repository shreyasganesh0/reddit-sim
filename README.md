# Reddit-Sim: A Distributed Reddit Simulator in Gleam

This project is an excellent demonstration of building a distributed, fault-tolerant application using Gleam and the underlying Erlang OTP framework. It simulates a basic Reddit-like system with a central server (the "engine") [cite: engine.gleam], multiple concurrent clients (the "users") [cite: users.gleam], and a dedicated metrics collector [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/metrics.gleam]. The entire system is built on the actor model, enabling robust state management and asynchronous communication between isolated processes.

## Core Concepts & Architectural Learnings

This project serves as a practical implementation of several fundamental principles of distributed systems and the OTP model:

Distributed Architecture (Erlang Nodes): The application is not a single monolith. It's designed to run as three separate, named Erlang nodes: engine@localhost (the server), client@localhost (the client simulator), and metrics@localhost (the logger) [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/start_engine.sh, shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/start_client.sh, shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/start_metrics.sh]. These nodes communicate over the network using Erlang's built-in distribution protocol, all orchestrated by Gleam.

Actor Model (gleam/otp/actor): The central server (engine.gleam), each individual user (users.gleam), and the metrics collector (metrics.gleam) are all implemented as OTP actors [cite: engine.gleam, users.gleam, shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/metrics.gleam].

Encapsulated State: The server's state (EngineState), each user's state (UserState), and the logger's state (MetricsState) are private to their respective actor processes.

Asynchronous Message Passing: All communication happens by sending immutable messages (e.g., RegisterUser, RecordLatency). This eliminates the need for locks or mutexes, simplifying concurrency.

Service Discovery (global): The engine and metrics actors, upon starting, register their Process IDs (PIDs) with the atom names "engine" and "metrics" in Erlang's global registry [cite: engine.gleam, shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/metrics.gleam]. When client actors start, they query this global registry (global_whereisname) to "find" the PIDs they need to communicate with [cite: users.gleam].

Fault Tolerance (supervisor): All three core actors (engine, metrics, and the pool of user actors) are started and managed by a supervisor [cite: engine.gleam, users.gleam, shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/metrics.gleam]. This is a cornerstone of OTP. If an actor crashes, the supervisor can restart it based on its defined strategy.

Metrics & Observability: The metrics actor acts as a sink for all performance data. User actors send latency timings and action counts (success/failure) after each operation [cite: users.gleam, shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/user_metrics.gleam]. The metrics actor also polls the engine for system-wide stats (total users, posts, etc.) [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/metrics.gleam]. All data is written to metrics.csv [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/metrics.gleam, metrics.csv] and can be plotted using the provided visualize.py script [cite: visualize.py].

Dynamic Simulation: The simulation is not driven by a static config file. Instead, each user actor runs its own "think loop" [cite: users.gleam]. User behavior is determined by roles ("creator", "lurker", "contributor") and a Zipf distribution to model realistic interaction patterns (e.g., popular subreddits are interacted with more) [cite: users.gleam, shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/client/zipf.gleam].

Graceful Shutdown: The simulation is designed to run for a fixed duration. The client node is given a run_time, after which it sends a shutdown message to all its user actors [cite: users.gleam]. As actors shut down, they notify both the engine and the client's main thread, allowing all three nodes to exit cleanly [cite: users.gleam, engine.gleam].

## Application Logic Flowchart

This flowchart illustrates the complete program flow, from initial launch to the message passing between all three nodes.

```
graph TD
    subgraph "Terminal 1: Server Node (engine@localhost)"
        A[sh start_engine.sh] --> B(gleam run -- server <num_users>)
        B --> C[reddit_sim.main]
        C --> D[engine.create]
        D --> E[supervisor.start]
        E --spawns--> F(Engine Actor)
        F --> G[engine.init]
        G --> H["global_register('engine', PID)"]
        H --> I{"engine.handle_engine (Loop)"}
        I --On RegisterUser--> J[Update EngineState]
        J --> K["utls.send_to_pid(ClientPID, Success)"]
        K --> I
        I --On ShutdownUser--> L[Increment counter]
        L --All users shutdown--> M[Send final stats to Metrics]
        M --> N[Send msg to main_sub]
        N --> O[actor.stop()]
        D --blocks on--> P[process.receive(main_sub)]
        N --> P
        P --> Q[Engine Exits]
    end

    subgraph "Terminal 2: Metrics Node (metrics@localhost)"
        R[sh start_metrics.sh] --> S(gleam run -- metrics)
        S --> T[reddit_sim.main]
        T --> U[metrics.create]
        U --spawns--> V(Metrics Actor)
        V --> W["global_register('metrics', PID)"]
        V --> X[Polls Engine for stats]
        V --> Y[Writes to metrics.csv]
        V --> Z{"metrics.handle_metrics (Loop)"}
    end

    subgraph "Terminal 3: Client Node (client@localhost)"
        AA[sh start_client.sh] --> BB(gleam run -- client simulator <num_users> <run_time>)
        BB --> CC[reddit_sim.main]
        CC --> DD["users.create(...)"]
        DD --> EE[supervisor.start]
        EE --spawns N times--> FF(User Actor)
        FF --> GG["users.init(id)"]
        GG --> HH["global_whereisname('engine')"]
        GG --> II["global_whereisname('metrics')"]
        II --> JJ{"users.handle_user (Loop)"}
        JJ --On RegisterUserSuccess--> KK[Starts 'think loop']
        KK --'think loop'--> LL[Selects action]
        LL --> MM["utls.send_to_engine(...)"]
        
        JJ --On Timer--> NN[InjectShutdownMessage]
        NN --> OO[utls.send_to_engine(ShutdownUser)]
        OO --> PP[Send msg to main_sub]
        PP --> QQ[actor.stop()]
        
        DD --blocks on--> RR[list.range()...process.receive(main_sub)]
        PP --> RR
        RR --All users shutdown--> SS[Client Exits]
    end

    subgraph "Network Communication"
        MM --Request--> I
        K --Reply--> JJ
        JJ --Metrics--> Z
        X --Metrics Request--> I
        I --Metrics Reply--> Z
        OO --Shutdown Msg--> I
        M --Final Stats--> Z
    end
```


## How to Build and Run

Follow these steps to build and run the Reddit simulator on your local machine.

Prerequisites

Gleam: Install the Gleam compiler.

Erlang/OTP: Install the Erlang runtime.

Python 3 & Pandas: Required for visualizing metrics.

pip install pandas matplotlib


1. Build the Project

A build script is provided to handle code generation and compilation.

```
./build.sh
```


This script first runs reddit-codegen/generate.sh and then runs gleam clean and gleam build in the reddit-sim directory.

2. Run the Application

This application must be run in three separate terminal windows. For a clean shutdown, it's recommended to run all scripts simultaneously (e.g., using a helper script that backgrounds processes).

IMPORTANT
```
cd reddit-sim
```
ALL FUTURE COMMANDS ASSUME THAT YOU ARE IN reddit-sim/

Terminal 1: Start the Engine (Server)
This terminal will run the central server process. The argument defines how many users it should wait for before shutting down.

```
# From the reddit-sim directory
# Usage: ./start_engine.sh <num_users>
./start_engine.sh
```


Terminal 2: Start the Metrics Logger
This terminal runs the metrics collector.

```
# From the reddit-sim directory
./start_metrics.sh
```


Terminal 3: Start the Clients (Simulator)
This terminal will run the client simulator, which spawns multiple user actors that connect to the engine and metrics nodes.

```
# From the reddit-sim directory
# Usage: ./start_client.sh <num_users> <run_time_ms>
./start_client.sh 1000 60000
```

This will simulate 1000 users for 60,000 milliseconds (1 minute).

You will see output in all three terminals as the clients are spawned, connect, and perform actions. After the run_time expires, all three processes will begin a graceful shutdown and exit.

3. Visualize the Results

After the simulation finishes, a metrics.csv file will be in your directory [cite: metrics.csv]. You can generate plots from it by running:

```
mkdir -p plots
python3 visualize.py
```

This will create four PNG images in a plots/ directory, showing system latency, throughput, and state size over time [cite: visualize.py].

## File & Module Breakdown

src/reddit_sim.gleam: Main entry point. Parses command-line arguments to determine whether to run as a server, client, or metrics node, and with what parameters [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/reddit_sim.gleam].

src/server/engine.gleam: The Server. Contains the Engine actor logic. It initializes the EngineState and processes all user requests (posts, votes, etc.) and shutdown messages [cite: engine.gleam].

src/client/users.gleam: The Client Simulator. Spawns and supervises N User actors. Each User actor is a state machine that finds the other nodes, holds its own UserState, and runs a "think loop" to perform actions based on its role [cite: users.gleam]. Manages the timed shutdown.

src/metrics/metrics.gleam: The Metrics Collector. Contains the Metrics actor, which listens for logs from all users, polls the engine, and periodically writes all collected data to metrics.csv [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/metrics.gleam].

src/metrics/user_metrics.gleam: A helper module for client-side metrics, providing functions to easily send formatted latency and health messages to the metrics actor [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/metrics/user_metrics.gleam].

src/client/zipf.gleam: A helper for the simulator, generating a Zipf distribution to model realistic user behavior [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/client/zipf.gleam].

src/utls.gleam: Shared utilities for sending messages, validating requests, and handling actors [cite: shreyasganesh0/reddit-sim/reddit-sim-b6fa65f810ae2ee592dc94d80a4d00a645790829/reddit-sim/src/utls.gleam].

visualize.py: A Python script to parse metrics.csv and generate performance graphs for analysis [cite: visualize.py].

Engineering Review & Future Improvements

Persistence: The EngineState is entirely in-memory. If the engine actor crashes, all user and subreddit data is lost. The next step would be to back this state with a database (e.g., Mnesia, a built-in Erlang DB, or an external DB like PostgreSQL).

Scalability: The single Engine actor is a bottleneck. It must process every single request for the entire application serially. A more scalable design would involve multiple actors, perhaps one actor per subreddit, managed by a Registry to route messages to the correct process.

Authentication: The current auth model relies on the engine trusting that a message from a specific PID corresponds to a UUID it has on file. This is not secure. A real system would implement a login flow that returns a session token (e.g., a JWT) which would be passed with every authenticated request.
