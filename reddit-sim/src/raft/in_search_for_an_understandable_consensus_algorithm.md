# In Search of an Understandable Consensus Algorithm

## Introduction
- Most consensus algorithms based on Paxos
- Paxos explanations and implementations require too many changes (multi-paxos) to make it practical
- Define a more understandable consensus algorithm
- Breaks down different components
    - log replication
    - leader election
    - safety
- Reduce the state space complexity
    - reduce number of ways of non determinism
- similar to viewstamped replication
- has novel features
    - strong leader
        - log entries only flow from leader to others
        - this simplifies replicated log handling
    - leader election
        - randomized timers to elect leaders
        - adds small overhead to heartbeat
        for faster and simplier conflict resolution
    - membership changes
        - uses joint consensus to change set of servers 
        in a cluster
        - majority of two different configurations overlap
        - allows operation during membership changes

## Replicated State Machines
- State machines on a collection of servers compute
identical copies of state
- can continue to run even if some servers are done
- state machines process commands sent from client
that are read from the log when replicated
- used in systems with single leader clusters
    - GPS, HDFS, RAMCloud
    - they use replicated state machines to 
    surivive leader crashes
    - chubby and zookeeper are replicated
    state machines
- usually implemented with a replicated log
    - each server stores a log with a series of commands
    - the commands are executed in order by the server
    - since state machines are deterministic they will
    have the same state if the log is consistent across 
    replicas
- keeping the log consistent is the job of the consensus
algorithmn
- the consensus module receives commands from the clients
    - adds it to the log
    - communicates with the consensus modules on other servers
    to ensure every log has the same commands in the same order
    - once commands are replicated the state machines process the
    commands and send responses to clients
- Properties of consensus algorithms
    - ensure safety (consistent correct results) under non byzantine
    failures
    - fully functional (availability) as long as majority of servers are operational
    and can communicate with each other
    - do not depend on timing for consistent logs (tolerant to faulty clocks and 
    delayed messages, causes delays in the worst case)
    - commands can complete as soon as a majority of servers respond to one round of
    requests

## Drawbacks of Paxos
- Paxos defines a protocol to acheive consensus on a single decision
- this decision is usually a single replicated log entry
    - this is called the single-decree Paxos
- multiple instances of this protocol are then combined to be applied
to an entire log
    - multi paxos
- it has 2 significant drawbacks
    - very difficult to understand
        - paxos is based of the single decree
            - this is split into two parts that cant be 
            explained seperately which makes it unintuitive
            - building consensus on a log can be decomposed
            more efficiently than the single-decree paxos
    - second there is no agreed upon implementation of multipaxos
        - systems like chubby that have implmeneted a paxos like consensus
        do not have details published
    - there is little to no reason to have the single-decree log entries
    be combined after the fact to form the log
    - more efficient to just build the system around the log
- paxos was also built based on p2p model (although it suggests a weak form of
leadership later)


## Raft
- Elect a leader
    - give the leader complete responsibility of handling the replicated log
    - accept log entries from clients
    - replicate them on servers
    - tells servers when it is safe to apply the log entries
- if a leader fails a new one is elected
- decomposed into 3 different subproblems
    - leader election
    - log replication
    - safety

### Raft basics
- contains several servers usually 5
- each server is in 1 of 3 states 
    - leader, follower, candidate
- normally only 1 leader
- followers dont issue requests only respond to leaders and candidates
- leader handles all client requests
    - if a client contacts a follower the follower forwards request to leader
    - candidate state used to elect a new leader
- time is dvided into arbitrary periods called terms
    - labelled with consecutive integers
    - each term begins with an election
    - one or more candidates trys to win the election
    - the winning candidate serves as the leader for the rest of the term
    - raft ensures at most one leader per term
        - if an election ends in a split vote no leader is chosen
        and a new term is started shortly after
    - different servers experience transtions between terms at different times
        - some servers may not even see entire terms
    - terms act as a logical clock
        - allow servers to detect stale leaders
        - each server stores a current term number that is monotonically increasing
        - term numbers are exchanged when communicating between servers
        - if one servers term number is smaller than the others then it increases
        its term to the larger seen term number
        - if a candidate or leader sees a larger term number it reverts to follower state
- two types of messages for basic consensus
    - RequestVote
        - sent by candidates during election
    - AppendEntries
        - sent by leaders to replicate log
    - retry messages if receive no response before timeout

### Leader Election
- Raft uses heartbeat (AppendEntries) to start election
- all servers start as followers
    - servers remain as followers as long as they receive a valid message from
    leader or candidate
    - leader sends heartbeats (AppendEntries with no log entries)
