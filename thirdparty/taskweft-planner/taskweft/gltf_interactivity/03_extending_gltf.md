## Extending glTF Object Model 

This Specification defines additional glTF Object Model pointers for use with `pointer/*` nodes.

### Implementation-Specific Runtime Limits 

TBD

### Active Camera State 

In some viewers, such as, but not limited to, augmented reality viewers and virtual reality viewers, the viewer implementation gives the user direct control over a virtual camera. This virtual camera **MAY** be controlled by user head movements, by movements of the user's phone with their hands, or by mouse, keyboard or touch input on a laptop, or by other means. It is useful for interactivity to be able to react to the position of this virtual camera.

This Specification defines the "active camera" as the camera transformation that ought to be reacted to by interactivity. When there is only one camera being displayed to the user the implementation **SHOULD** use this camera as the "active camera". When there are multiple cameras being controlled by the user, the implementation **MAY** select one such camera or construct a synthetic camera to use as the "active camera" (for example the midpoint of two stereoscopic camera positions). When zero cameras are being controlled by the user but views from one or more cameras are being displayed to the user, the implementation **SHOULD** select one of the cameras that is being displayed as the "active camera".

The `position` read-only property represents the "active camera" position in the global space using the glTF coordinate system. The `rotation` read-only property represents the "active camera" rotation quaternion (using XYZW notation); the identity quaternion corresponds to the camera orientation defined in the glTF 2.0 Specification.

An implementation **MAY** provide no "active camera" data, for example for privacy reasons or if no cameras are being displayed to the user. If the "active camera" position is unavailable, the `position` property **MUST** be set to all NaNs; if the "active camera" rotation is unavailable, the `rotation` property **MUST** be set to all NaNs.

The following pointers represent the properties defined in this section.

+-------------------------------------------------------+---------------+
| Pointer                                               | Type          |
+=======================================================+===============+
| `/extensions/KHR_interactivity/activeCamera/rotation` | `float4`      |
+-------------------------------------------------------+---------------+
| `/extensions/KHR_interactivity/activeCamera/position` | `float3`      |
+-------------------------------------------------------+---------------+

### Animation State 

To efficiently control animations, graphs usually need to access various states specific to glTF animation objects. The interactivity extension adds the following five runtime properties to the glTF animation objects.

The `isPlaying` read-only property is true when the animation is playing, false otherwise.

The `minTime` and `maxTime` read-only properties represent the timestamps of the first and the last keyframes as stored in the glTF animation object. The values **MUST** be derived from the `min` and `max` properties of the used sampler input accessors. Unused animation samplers, i.e., samplers not referenced by the animation channels, **MUST** be ignored. If the animation object is invalid as defined in the core glTF 2.0 specification, these properties **MUST** return NaNs.

The `playhead` read-only property represents the current animation position within the glTF animation data. For valid glTF animations, the property value is equal to the last effective timestamp, so it is always greater than or equal to zero and less than or equal to `maxTime`. Before the animation start, this property value is zero; when the animation stops, the property retains its last value until the animation is restarted. For invalid glTF animations, the property value is always NaN.

The `virtualPlayhead` read-only property represents the current animation position on the infinite timeline that is used for the input value sockets of the `animation/start` and `animation/stop` operations. For valid glTF animations, the property value is equal to the last requested timestamp. Before the animation start, this property is zero; when the animation stops, the property value retains its last value until the animation is restarted. For invalid glTF animations, the property value is always NaN.

The following pointers represent the properties defined in this section.

+---------------------------------------------------------------+---------------+
| Pointer                                                       | Type          |
+===============================================================+===============+
| `/animations//extensions/KHR_interactivity/isPlaying`       | `bool`        |
+---------------------------------------------------------------+---------------+
| `/animations//extensions/KHR_interactivity/minTime`         | `float`       |
+---------------------------------------------------------------+---------------+
| `/animations//extensions/KHR_interactivity/maxTime`         | `float`       |
+---------------------------------------------------------------+---------------+
| `/animations//extensions/KHR_interactivity/playhead`        | `float`       |
+---------------------------------------------------------------+---------------+
| `/animations//extensions/KHR_interactivity/virtualPlayhead` | `float`       |
+---------------------------------------------------------------+---------------+

# JSON Syntax 

## General 

A `KHR_interactivity` extension object is added to the root-level `extensions` property. It contains an array of interactivity graphs each element of which contains five arrays corresponding to five interactivity concepts: `types`, `variables`, `events`, `declarations`, and `nodes`, and an optional `graph` property that selects the default graph to use.

Different elements of the `graphs` array are completely isolated from each other and exist in separate scopes. One invalid graph does not invalidate other elements of the `graphs` array.

As with the core glTF spec, if a JSON array is empty, it **MUST** be omitted from JSON.

``` highlight
{
  "asset": {
    "version": "2.0"
  },
  "extensionsUsed": [ "KHR_interactivity" ],
  "extensions": {
    "KHR_interactivity": {
      "graphs": [
        {
          "types": [
            //
          ],
          "variables": [
            //
          ],
          "events": [
            //
          ],
          "declarations": [
            //
          ],
          "nodes": [
            //
          ]
        }
      ],
      "graph": 0
    }
  }
}
```

The `graph` property refers to the `graphs` array element that **SHOULD** be selected by default by the execution environment. If the `graph` property is undefined, its value is implicitly set to zero. If the `graph` property is negative or greater than the number of elements in the `graphs` array, the interactivity extension object is invalid.

If the currently selected graph is invalid or if the interactivity extension object is invalid, implementations **MAY** treat the asset as not having interactivity at all.

## Types 

The `types` array defines mappings between type indices used by the graph and the recognized type signatures. Each entry in this array denotes a distinct type.

The value of the `signature` property **MUST** be one of the value types defined in this extension specification or `"custom"`. In the latter case, the custom type semantics **MUST** be provided by an additional extension.

Values of the `signature` property are case-sensitive.

Non-custom signatures **MUST NOT** appear more than once in this array; if two or more entries of the `types` array have the same non-custom signature, the graph is invalid and **MUST** be rejected. Extensions or extras present on the types defined by this Specification do not change type semantics.

## Variables 

The `variables` array defines variables with their types and optional initial values.

The type of the variable is determined by the **REQUIRED** `type` property that points to the element of the `types` array. If the `type` property is undefined or its value is negative or greater than or equal to the length of the `types` array\`, the variable is invalid and the graph **MUST** be rejected.

The `value` property is an array that defines the initial variable value. If the `value` property is undefined, the variable is initialized to the default value of its type. The following table defines array lengths and default values for all value types defined in this Specification.

+-----------------+-----------------+-----------------------------------+
| Type            | Array length    | Default value                     |
+=================+=================+===================================+
| `bool`          | 1               | Boolean false                     |
+-----------------+-----------------+-----------------------------------+
| `float`         | 1               | Floating-point NaN                |
+-----------------+-----------------+-----------------------------------+
| `float2`        | 2               | Two floating-point NaNs           |
+-----------------+-----------------+-----------------------------------+
| `float3`        | 3               | Three floating-point NaNs         |
+-----------------+-----------------+-----------------------------------+
| `float4`        | 4               | Four floating-point NaN           |
+-----------------+-----------------+-----------------------------------+
| `float2x2`      | 4               | Four floating-point NaNs          |
+-----------------+-----------------+-----------------------------------+
| `float3x3`      | 9               | Nine floating-point NaNs          |
+-----------------+-----------------+-----------------------------------+
| `float4x4`      | 16              | Sixteen floating-point NaNs       |
+-----------------+-----------------+-----------------------------------+
| `int`           | 1               | Integer zero                      |
+-----------------+-----------------+-----------------------------------+

Values for vector types use the XYZW order of components, that is X component is stored in the array element with index 0, Y component is stored in the array element with index 1, and so forth.

Values for matrix types use the column-major order of elements. For example, elements of a 2x2 matrix are stored as `[c0r0, c0r1, c1r0, c1r1]`, where `c0r0` is the element in the first column and first row, `c0r1` is the element in the first column and second row, and so forth.

If the `value` property array length does not match the array length for the specified type, the variable is invalid and the graph **MUST** be rejected.

If the variable type is **bool** and the only array element is not a JSON boolean literal, i.e., neither `true` nor `false`, the variable is invalid and the graph **MUST** be rejected.

If the variable type is any of the **floatN** or **floatNxN** types and any of the array elements is not a JSON number, the variable is invalid and the graph **MUST** be rejected.

If the variable type is **int** and the only array element is not a JSON number exactly representable as a 32-bit signed integer, the variable is invalid and the graph **MUST** be rejected.

If the variable type is custom, the `value` property is defined by the extension defining the custom type.

## Events 

The `events` array defines external ids and value sockets for custom events.

The event id is an application-specific event identifier recognized by the execution environment. If the `id` property is undefined, the event is considered internal to the graph. If the same id is defined for two or more events, the graph is invalid and **MUST** be rejected.

The properties of the `values` object define ids and the values of those properties define types and optional initial values of the value sockets associated with the event. If the `values` object is undefined, the event has no associated value sockets.

Socket ids defined by the properties of the `values` object are case-sensitive.

The type of the event value socket is determined by the **REQUIRED** `type` property that points to the element of the `types` array. If the `type` property is undefined or its value is negative or greater than or equal to the length of the `types` array, the event is invalid and the graph **MUST** be rejected.

The `value` property of the event value socket has the same syntax and semantics as the `value` property of variable definitions (see the previous section).

## Declarations 

The `declarations` array defines mappings between node declaration indices used by the graph and the operations.

The `op` property is **REQUIRED**; it contains the operation identifier; if this property is undefined, the declaration is invalid and the graph **MUST** be rejected.

Values of the `op` property are case-sensitive.

If the operation is not defined by this Specification, the `extension` property **MUST** be defined and it contains the additional interactivity extension name that defines the operation. If the `extension` property is not defined and the operation is not defined by this Specification, the declaration is invalid and the graph **MUST** be rejected.

Values of the `extension` property are case-sensitive.

If the operation is defined in an additional interactivity extension and it uses input value sockets, the `inputValueSockets` object **MUST** be present. Its properties define ids and the values of its properties define types of the input value sockets. If the `inputValueSockets` object is undefined, the operation has no input value sockets.

If the operation is defined in an additional interactivity extension and it uses output value sockets, the `outputValueSockets` object **MUST** be present. Its properties define ids and the values of its properties define types of the output value sockets. If the `outputValueSockets` object is undefined, the operation has no output value sockets.

Socket ids defined by the properties of the `inputValueSockets` and `outputValueSockets` objects are case-sensitive.

If the `extension` property is undefined, the operation with all its value sockets is assumed to be provided by this Specification and therefore `inputValueSockets` and `outputValueSockets` objects **MUST NOT** be defined.

The type of the value socket is determined by the **REQUIRED** `type` property that points to the element of the `types` array. If the `type` property is undefined or its value is negative or greater than or equal to the length of the `types` array, the declaration is invalid and the graph **MUST** be rejected.

Two declarations are considered equal if their `op` properties have the same value, their `extension` properties (if present) have the same value, and their `inputValueSockets` objects (if present) define the same socket ids with the same type indices. The `declarations` array **MUST NOT** have equal declarations; if two or more declarations are equal, all of them are invalid and the graph **MUST** be rejected.

### Unsupported Declarations 

A declaration is considered unsupported if any of the following conditions is true:

- The declaration refers to an unsupported or disabled extension.

- The referred extension does not define the operation.

- Neither of the definitions of the operation in the referred extension has exactly the same input and output value sockets with regards to their ids and types.

If the declaration is unsupported, the nodes referring to it are demoted to ["no-op" nodes](#nodes-noop).

## Nodes 

The `nodes` array defines the nodes and their connections.

Each element of the `nodes` array specifies the node's operation via a declaration index, sources for the input value sockets, pointers for the output flow sockets, and its configuration.

### Operation 

The operation is specified by the **REQUIRED** `declaration` property that points to an element of the `declarations` array. If that property is undefined or its value is negative or greater than or equal to the number of declarations, the node is invalid and the graph **MUST** be rejected.

### Input Value Sockets 

If the operation has input value sockets, the `values` object **MUST** be defined and it **MUST **have properties matching the input value socket ids defined by the declaration and/or configuration; if the `values` object does not have a corresponding property for each input value socket id, the node is invalid and the graph** MUST **be rejected. The `values` object** MAY **have additional properties not matching the input value socket ids of the operation; such properties have no effect on the operation but their values** MUST **still conform to the JSON schema and other rules defined in this section. If the operation does not have input value sockets, the `values` object** SHOULD NOT**\* be defined.

Some operations, e.g., `pointer/get` or `variable/get`, define their input value socket ids and/or types based on the node's configuration. Therefore, the configuration **MAY** need to be processed prior to the input value sockets.

The values of the `values` object properties are JSON objects that define effective input value socket types and value sources. Each value source is either an inline constant value, a [type-default](#variables-types) value, or a reference to another node's output value socket. If no source is defined or if the socket type does not match the declaration, the node is invalid and the graph **MUST** be rejected.

Socket ids defined by the properties of the `values` object are case-sensitive.

Some nodes have multiple variants to support the same operation on different input value socket types. In all such cases, the variants share the same set of input value socket ids and only their types differ. Therefore, effective input value socket types **MAY** be needed to fully resolve the operation.

If the operation does not support the input value socket types used by the node, the node is invalid and the graph **MUST** be rejected.

#### Inline Values 

If the `value` property is defined in the object representing the input value socket, the input value socket source is an inline constant.

The `value` property has the same syntax as the `value` property of variable definitions. The type of the input value socket is determined by the `type` property that points to the element of the `types` array and **MUST** be defined. If the `type` property value is negative or greater than or equal to the number of types, the node is invalid and the graph **MUST** be rejected.

#### Output Socket References 

If the `node` property is defined in the object representing the input value socket, the input value socket source is the output value socket of another node of the graph. If both `node` and `value` properties are defined for the same input value socket, the node is invalid and the graph **MUST** be rejected.

The `node` property contains the index of the other node and the `socket` property contains the id of the output socket of that node.

If the `node` property value is negative or greater than or equal to the index of the current node, the node is invalid and the graph **MUST** be rejected.

If the `socket` property is defined, it **MUST** correspond to an output value socket existing in the referenced node, otherwise the current node is invalid and the graph **MUST** be rejected. If the `socket` property is undefined, the default socket id `"value"` is used implicitly. Therefore, if the referenced node does not have an output value socket with id `"value"`, the `socket` property **MUST** be defined.

Socket ids referenced by the `socket` property are case-sensitive.

If both `node` and `type` properties are defined, the type referred by the `type` property **MUST** match the type of the referenced output value socket; if the types do not match, the current node is invalid and the graph **MUST** be rejected.

#### Type-Default Values 

If neither `value` nor `node` properties are defined in the object representing the input value socket, the input value socket has a [type-default](#variables-types) value determined by the `type` property that points to the element of the `types` array and **MUST** be defined. If the `type` property value is negative or greater than or equal to the number of types, the node is invalid and the graph **MUST** be rejected.

### Output Flow Socket Pointers 

Pointers for the output flow sockets are defined in the `flows` object of the node.

Properties of the `flows` object link output flow sockets of the current node with input flow sockets of other nodes. If an output flow socket id of the current node is not present in the `flows` object, that output flow socket is unconnected and activating it has have no effect.

Socket ids defined by the properties of the `flows` object are case-sensitive.

The `flows` object **MAY** contain properties not corresponding to output flows of the current node; such properties do not affect functionality of the node but their values **MUST** still be validated as described below.

Each property of the `flows` object is a JSON object containing a **REQUIRED** `node` property and an **OPTIONAL** `socket` property. The `node` property contains the index of the other node and the `socket` property contains the id of the input flow socket of that node.

Socket ids referenced by the `socket` property are case-sensitive.

The `node` property value **MUST** be greater than the index of the current node and less then the total number of nodes, otherwise the node is invalid and the graph **MUST** be rejected.

If the `socket` property is undefined, it has a default value of `"in"`.

If the `socket` property value corresponds to an input flow socket existing in the referenced node, the output flow socket of the current node is connected to the referenced input flow socket. If the specified input flow socket does not exist in the referenced node, the output flow socket of the current node is unconnected and activating it **MUST** have no effect.

### Configuration 

Configuration properties are defined in the `configuration` object of the node.

Each property of the `configuration` object is a JSON object with a single `value` property. The type of the `value` property is determined by the node's specification, i.e., configuration values are implicitly typed.

Refer to the [Configuration](#nodes-configuration) section and to individual node specifications for details regarding configuration validity.

Configuration properties defined by the properties of the `configuration` object are case-sensitive.

Configuration values use JSON arrays similarly to other uses of inline values.

+----------------------+------------------------------------------------------------------------------+
| Configuration Type   | JSON Type                                                                    |
+======================+==============================================================================+
| `bool`               | Array of one boolean                                                         |
+----------------------+------------------------------------------------------------------------------+
| `int`                | Array of one number exactly representable as a 32-bit signed integer         |
+----------------------+------------------------------------------------------------------------------+
| `int[]`              | Array of one or more numbers exactly representable as 32-bit signed integers |
+----------------------+------------------------------------------------------------------------------+
| `string`             | Array of one JSON string                                                     |
+----------------------+------------------------------------------------------------------------------+

# Validation (Informative) 

This section describes steps needed to check validity of the interactivity extension object according to the normative language of the previous sections and the corresponding JSON schemas.

Last updated 2026-01-01 17:23:20 -0800
