## Graphs 

A behavior graph is a JSON object containing *nodes*. It **MAY** also contain custom variables and custom events.

Behavior graphs are directed graphs with no directed cycles.

When a glTF asset contains a behavior graph, all glTF animations are assumed to be controlled by the graph so they **MUST NOT** play automatically.

## Nodes

A *node* is a JSON object, which represents an executable item. Each node is defined by its *declaration*, which includes an *operation* and a (possibly empty) set of *value sockets*. Node operations follow `domain/operation` naming pattern. Depending on the operation, a node **MAY** have input and/or output *flow sockets*; they **MAY** be affected by the node's *configuration*.

### Operation 

A node's *operation* defines a specific set of steps performed by the execution environment when the node is executed.

A node is executed when one of its input flow sockets is activated, when one of its output value sockets is accessed by another node, when an operation-specific event occurs. A node **MAY** repeatedly activate its own input flow sockets during the execution.

Usually, the node execution includes evaluating its input value sockets (if any), processing its own logic, and activating any number (including zero) of output flow sockets.

### Sockets 

There are four kinds of sockets.

*Output value sockets* represent data initialized by the node or produced during its execution. For example, it could be results of math operations or parts of the node's internal state. Accessing these sockets either triggers computing the return value on the fly by executing the node or returns a value based on the node's internal state. Exact behavior depends on the node's operation. As a general rule, output value sockets **MUST** retain their values until a node with one or more flow sockets is executed.

*Input value sockets* represent data accessed during the node's execution. For example, it could be arguments of math operations or execution parameters such as iteration count for loop nodes or duration for time-related nodes. Each of these sockets **MUST** either be given an inline constant value in the node object or connected to an output value socket of a different node. The node **MAY** access its input value sockets multiple times during the execution. The runtime **MUST** guarantee that all input value sockets have defined values when the node execution starts.

*Output flow sockets* represent "function pointers" that the node will call to advance the graph execution. For example, bodies and branches of flow control nodes are output flow sockets that drive further execution when certain condition are fulfilled. An output flow socket is either connected to exactly one input flow socket of another node or unconnected; in the latter case activating the output flow socket is a no-op.

*Input flow sockets* represent "methods" that could be called on the node. For example, flow control nodes (such as loops and branches) usually have an `in` input flow socket that starts node's execution. Additional input flow sockets **MAY** exist such as `reset` for nodes having an internal state. An input flow socket is either connected to one or more output flow sockets of other nodes or unconnected; in the latter case the node's "method" represented by the socket is never called.

Input and output value sockets have associated data types, e.g., floats, integers, booleans, etc.

Socket ids exist in four separate scopes corresponding to the four socket kinds.

#### Socket Order

Although sockets are inherently unordered within a node (because JSON properties are unordered), some operations such as `flow/sequence` or `flow/multiGate` need a specific socket order to guarantee predictable behavior. In such cases, the sockets are implicitly sorted by their ids in ascending order.

For any given ids `a` and `b`, the following procedure **MUST** be used to determine if `a` is less than `b`.

1.  Let *unitsA* and *unitsB* be the sequences of UTF-16 code units corresponding to the socket ids `a` and `b` respectively and *lengthA* and *lengthB* be the lengths of these sequences.

2.  Let *minLength* be the minimum of *lengthA* and *lengthB*.

3.  For each integer *i* such that 0 ≤ *i* \< *minLength*, in ascending order, do

    a.  if *unitsA\[i\]* \< *unitsB\[i\]* return true;

    b.  if *unitsA\[i\]* \> *unitsB\[i\]* return false.

4.  If *lengthA* \< *lengthB* return true.

5.  Return false.

#### Value Socket Types 

All value sockets are strictly typed.

Implementations of this extension **MUST** support the following type signatures.

bool

float

float2

float3

float4

float2x2

float3x3

float4x4

int

### Configuration 

Nodes **MAY** be configurable through inline properties collectively called *configuration* that **MAY** affect the node's behavior and the number of its sockets, such as the set of cases for the `flow/switch` node.

If a node specification does not include any configuration, the node is not configurable and any configuration properties defined for it in the behavior graph **MUST** be ignored.

Unless specified otherwise, all nodes that include configuration have a *default* configuration. The default configuration **MUST** be used when the behavior graph does not provide any configuration or when the provided configuration is invalid. If a node does not have a default configuration (like `variable/*` nodes) and the behavior graph does not provide a valid configuration, the whole graph is invalid and **MUST** be rejected.

For a configuration to be valid, all configuration properties defined by the node specification **MUST** be provided in the behavior graph with valid types and values. If any of the configuration properties defined by the node specification is omitted or has invalid type or invalid value, the whole configuration is invalid and the node behavior **MUST** fall back to the default configuration if the latter is supported. Configuration properties present in the behavior graph but not defined by the node specification **MUST** be ignored.

Implementations **SHOULD** generate appropriate warnings as deemed possible when:

- a non-configurable node has a configuration in the behavior graph;

- a provided configuration contains unknown properties;

- a provided configuration is invalid.

#### Configuration Types 

Configuration properties use a separate type system unrelated to the value socket types.

bool

int

int\[\]

string

### Unsupported Operations 

If the execution environment does not support the operation, e.g., when the operation is defined by an unsupported or disabled extension for the Interactivity Specification, the operation is implicitly replaced with a "no-op" operation defined as follows:

- activating the node's input flow sockets is ignored;

- the node's output flow sockets are never activated;

- the node's output value sockets have constant [type-default](#variables-types) values.

## Custom Events 

A behavior graph **MAY** define custom events for interacting with external execution environments and/or creating asynchronous loops.

A custom event definition includes its value sockets with types and optional initial values as well as an optional unique string identifier for linking the event with the external environment.

Semantics of custom events are application-specific.

## Custom Variables 

A behavior graph **MAY** define custom variables. A variable **MAY** be declared simultaneously with its initial value, otherwise the variable **MUST** be initialized to the type-specific default.

Custom variables **MUST** retain their values until the graph execution is terminated.

### Custom Variable Types 

Custom variables use the same type system as the value sockets. The following table defines type-default values.

+----------------------+-----------------------------------------------+
| Type                 | Default value                                 |
+======================+===============================================+
| `bool`               | Boolean false                                 |
+----------------------+-----------------------------------------------+
| `float`              | Floating-point NaN                            |
+----------------------+-----------------------------------------------+
| `float2`             | Two floating-point NaNs                       |
+----------------------+-----------------------------------------------+
| `float3`             | Three floating-point NaNs                     |
+----------------------+-----------------------------------------------+
| `float4`             | Four floating-point NaNs                      |
+----------------------+-----------------------------------------------+
| `float2x2`           | Four floating-point NaNs                      |
+----------------------+-----------------------------------------------+
| `float3x3`           | Nine floating-point NaNs                      |
+----------------------+-----------------------------------------------+
| `float4x4`           | Sixteen floating-point NaNs                   |
+----------------------+-----------------------------------------------+
| `int`                | Integer zero                                  |
+----------------------+-----------------------------------------------+

## Implementation-Specific Limits 

### Static Limits 

Implementations **MAY** restrict the size and complexity of behavior graphs by imposing certain limits on the following statically-known properties:

- The number of types

- The number of variables

- The number of custom events and the number of value sockets within a custom event

- The number of operation declarations

- The number of input and output value sockets in operation declarations

- The number of nodes

- The number of graph-defined output flow sockets in operations like `flow/multiGate` or `flow/sequence`

- The number of configuration-defined output flow sockets in operations like `flow/switch`

- The number of configuration-defined input value sockets in operations like `pointer/get`, `math/switch`, or `variable/set`

The graph **MUST** be rejected if it exceeds implementation-defined max values for these properties.

### Dynamic Limits 

Implementations **MAY** restrict the runtime capabilities of behavior graphs by imposing certain limits on the following features that require dynamic allocation of memory and/or processing power:

- Numbers of simultaneous delays, animations, and interpolations; exceeding these limits results in runtime errors that can be gracefully handled by the graph itself, see `err` output flows of the corresponding nodes.

- Number of events processed within a single rendered frame; exceeding this limit **MAY** result in an implementation-specific behavior such as reducing the frame rate or rescheduling the extra events.

These limits are exposed to behavior graphs via additional glTF Object Model pointers.

# Functional Specification 

Last updated 2026-01-01 17:23:19 -0800
