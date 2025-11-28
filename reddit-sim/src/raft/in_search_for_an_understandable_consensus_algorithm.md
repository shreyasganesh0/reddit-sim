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
    - leader sends heartbeats (AppendEntries with no log entries) to maintain authority
    - if a server doesnt receive a heartbeat from the leader withing the election timeout
    it will start an election
- Election
    - increment its term
    - transition to candidate state
    - it votes for itself and sends a RequestVote message in parallel to all servers in the cluster
    - stays in candidate state until
        - wins the election
            - wins the election if it gets majority votes
            - each server votes for at most one candidate per term
            - majority ensures at most one candidate can win
            - when it wins it becomes a leader and sends a heartbeat to all other candidates
        - another server establishes itself as the leader
            - while waiting for votes it may receive a AppendEntries heartbeat from another leader
            - if that leaders term is atleast as large as the current term then it accepts that
            server as the leader and returns to follower state
        - a period of time goes by without a winner
            - if split votes occur then the candidates timeout and restart as election
            - to prevent indefinite retries raft uses randomized timeouts
                - chosen randomly between (150 - 300ms)
            - the random timeout is used for both start of election when no heartbeat
            is received or if a split vote occurs

### Log Replication
- Once the leader has been elected it services client requests
- request command appended to leaders log
- leader issues AppendEntries
- when the entry is replicated leader applies the command
to its state machine and returns a result to a client
    - leader retries entry to clients until they send back ack
    - even if the client crashes the leader keeps retrying

- log entries are: State machine command + term number + integer index in log
- once the leader decides a log entry is safe to apply it is commited
    - commands are commited once the leader receives majority confirmations
    - all previous commands are also commited once this command is commited
    - including all entries from previous leaders
- leader tracks highest known index that it has comitted
    - the index is included in future AppendEntries
    - if a follower sees the index it applies all entries up till that point to its state machine
- LOG MATCHING PROPERTY
    - if 2 entries have the same index and term on different servers, they store the same command
        - garunteed by leader must create at most one entry per index per term
    - if 2 entries have the same index and term on different servers, 
        - maintained by AppendEntries message including highest seen index and term 
        before the new changes
        - if the follower does not seen the entry for that term and index in its log it rejects
        the AppendEntries for the new entries
    - the base case when logs are empty matches this property
    - by induction all future states must maintain the log matching property
- If a leader crashes followers may have entries that werent commited in the leader since
it didnt receive all replica confirmations before crashing
    - to handle this case the leader forces followers to replicate its log
    - it overwrites the log entries of followers
        - it must find the latest log entry where they both agree
        - delete any entries in the followers log after that point
        - these happen during the consistency check with AppendEntries
        - leader maintains a nextIndex per follower
            - index of next log entry that the leader will send to that follower
        - after it comes back to life it initializes all nextIndex entries 
        to the index right after the latest index in its log
        - If it receives any Reject messages from the AppendEntries
            - it logs the nextIndex and retries for that follower
            - eventually by reducing the nextIndex to send to that follower
            the logs will reach a state where both are consistent (leader and follower logs)
            - once they agree that AppendEntries message will erase all inconsistent logs in the follower
            - it will then update all entries from the leader to the follower
        - this process can be optimized by the follower sending the first index and term that it has
        in the rejection message
            - this will allow one message per term instead of one per index
    - the leader upholds append only feature for its log (never overwrites any of its entries)

### Log Safety
- Safety of data where a follower crashes and a leader replicates and changes state
    - then when the crashed follower comesback it might become the leader and overwrite these entries
    - this could lead to inconsistent state if any leader does not have the commited state of previous
    leaders
- need a property called leader completeness property to hold 
    - ever new leader has all commited log entries commited in its state up until that point
- This can be implemented using
    - Election restriction
        - usual algorithms allow lagging leaders to receive the entries that are missing 
        and makes them update themselves if such a scenario happens
        - raft garuntees opposite where any leader must have all commited entries 
        at the time of election
        - it does this by not allowing candidates to exist that dont have all log 
        entries commited
        - The RequestVote message implements this restriction
            - if the current the votes log is more uptodate than the leaders
            log then it rejects the vote request
- Committing from a previous term
    - 
        

