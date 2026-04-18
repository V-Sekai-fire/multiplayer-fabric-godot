# Validation Glossary 

This section uses the following terms:

assert

JSON index

reject the extension

reject the graph

# Extension Object Validation 

1.  *Assert* that the interactivity extension object has the `graphs` property that is a non-empty JSON array.

2.  Validate each element of the `graphs` array as described in [Graph Object Validation](#validation-graph-object).

3.  If the interactivity extension object has the `graph` property:

    1.  *assert* that the `graph` property value is a *JSON index*;

    2.  if the `graph` property value is not less than the `graphs` array length,

        1.  *reject the extension*;

    3.  if the graph referenced by the `graph` property value is invalid,

        1.  *reject the extension*.

# Graph Object Validation 

1.  *Assert* that the element of the `graphs` array is a JSON object ("the graph").

2.  If "the graph" object has the `types` property:

    1.  *assert* that the `types` property is a non-empty JSON array;

    2.  if the `types` array length is greater than the implementation-specific limit on the number of used types, *reject the graph*;

    3.  for each element of the `types` array:

        1.  *assert* that the element of the `types` array is a JSON object ("the type");

        2.  *assert* that "the type" object has the `signature` property that is a JSON string;

        3.  if the `signature` property value is not `"bool"`, `"custom"`, `"float"`, `"float2"`, `"float3"`, `"float4"`, `"float2x2"`, `"float3x3"`, `"float4x4"`, or `"int"`,

            1.  *reject the graph*;

    4.  if two or more elements of the `types` array have the same `signature` value that is not `"custom"`,

        1.  *reject the graph*.

3.  If "the graph" object has the `variables` property:

    1.  *assert* that the graph has the `types` property;

    2.  *assert* that the `variables` property is a non-empty JSON array;

    3.  if the `variables` array length is greater than the implementation-specific limit on the number of variables,

        1.  *reject the graph*;

    4.  validate each element of the `variables` array as described in the [Variable Object Validation](#validation-variable-object) section.

4.  If "the graph" object has the `events` property:

    1.  *assert* that the `events` property is a non-empty JSON array;

    2.  if the `events` array length is greater than the implementation-specific limit on the number of event definitions,

        1.  *reject the graph*;

    3.  validate each element of the `events` array as described in the [Event Object Validation](#validation-event-object) section;

    4.  if two or more elements of the `events` array have the same `id` value that is not undefined,

        1.  *reject the graph*.

5.  If "the graph" object has the `declarations` property:

    1.  *assert* that the `declarations` property is a non-empty JSON array;

    2.  if the `declarations` array length is greater than the implementation-specific limit on the number of declarations,

        1.  *reject the graph*;

    3.  validate each element of the `declarations` array as described in the [Declaration Object Validation](#validation-declaration-object) section.

6.  If "the graph" object has the `nodes` property:

    1.  *assert* that the `nodes` property is a non-empty JSON array;

    2.  if the `nodes` array length is greater than the implementation-specific limit on the number of nodes,

        1.  *reject the graph*;

    3.  validate each element of the `nodes` array as described in the [Node Object Validation](#validation-node-object) section.

# Variable Object Validation 

1.  *Assert* that the element of the `variables` array is a JSON object ("the variable").

2.  *Assert* that "the variable" object has the `type` property that is a *JSON index*.

3.  If the `type` property value is not less than the `types` graph array length,

    1.  *reject the graph*.

4.  If the "the variable" object has the `value` property:

    1.  *assert* that the `value` property is a non-empty JSON array;

    2.  validate the `value` property value according to the [Inline Value Validation](#inline-value-validation) section using the `type` property value.

# Event Object Validation 

1.  *Assert* that the element of the `events` array is a JSON object ("the event").

2.  If "the event" object has the `id` property,

    1.  *assert* that the `id` property value is a JSON string.

3.  If "the event" object has the `values` property,

    1.  *assert* that the `values` property is a non-empty JSON object;

    2.  if the `values` object has more properties than the implementation-specific limit on the number of event value sockets,

        1.  *reject the graph*;

    3.  for each property of the `values` JSON object:

        1.  *assert* that the property is a JSON object ("the event value");

        2.  *assert* that "the event value" object has the `type` property that is a *JSON index*;

        3.  if the `type` property value is not less than the `types` graph array length,

            1.  *reject the graph*;

        4.  if the "the event value" object has the `value` property:

            1.  *assert* that the `value` property is a non-empty JSON array;

            2.  validate the `value` property value according to the [Inline Value Validation](#inline-value-validation) using the `type` property.

# Declaration Object Validation 

1.  *Assert* that the element of the `declarations` array is a JSON object ("the declaration").

2.  *Assert* that "the declaration" object has the `op` property that is a JSON string.

3.  If "the declaration" object does not have the `extension` property:

    1.  if the `op` property value does not match any operation defined in this Specification,

        1.  *reject the graph*;

    2.  if "the declaration" object has the `inputValueSockets` and/or `outputValueSockets` properties,

        1.  *reject the graph*;

4.  If "the declaration" object has the `extension` property:

    1.  *assert* that the `extension` property is a JSON string;

    2.  if the "the declaration" object has the `inputValueSockets` property:

        1.  *assert* that the `inputValueSockets` property is a non-empty JSON object;

        2.  if the `inputValueSockets` object has more properties than the implementation-specific limit on the number of input value sockets for declarations,

            1.  *reject the graph*;

        3.  *assert* that the graph has the `types` property;

        4.  for each property of the `inputValueSockets` JSON object:

            1.  *assert* that the property is a JSON object ("the input value socket declaration");

            2.  *assert* that "the input value socket declaration" object has the `type` property that is a *JSON index*;

            3.  if the `type` property value is not less than the `types` graph array length,

                1.  *reject the graph*;

    3.  if "the declaration" object has the `outputValueSockets` property:

        1.  *assert* that the `outputValueSockets` property is a non-empty JSON object;

        2.  if the `outputValueSockets` object has more properties than the implementation-specific limit on the number of output value sockets for declarations,

            1.  *reject the graph*;

        3.  *assert* that the graph has the `types` property;

        4.  for each property of the `outputValueSockets` JSON object:

            1.  *assert* that the property is a JSON object ("the output value socket declaration");

            2.  *assert* that "the output value socket declaration" object has the `type` property that is a *JSON index*;

            3.  if the `type` property value is not less than the `types` graph array length,

                1.  *reject the graph*.

# Node Object Validation 

1.  *Assert* that the element of the `nodes` array is a JSON object ("the node").

2.  *Assert* that "the node" object has the `declaration` property that is a JSON index.

3.  If the `declaration` property value is not less than the `declarations` graph array length,

    1.  *reject the graph*.

4.  If "the node" object has the `configuration` property:

    1.  *assert* that the `configuration` property is a non-empty JSON object;

    2.  for each property of the `configuration` JSON object:

        1.  *assert* that the property is a JSON object ("the configuration property");

        2.  *assert* that "the configuration property" object has the `value` property that is a non-empty JSON array.

5.  If the node is configurable as indicated by the operation referenced by the `declaration` property and the node does not support a default configuration:

    1.  if "the node" does not have the `configuration` property,

        1.  *reject the graph*;

    2.  if `configuration` object is not valid as defined by the node,

        1.  *reject the graph*.

6.  If the node is configurable, the configuration affects the node's sockets, and applying the specified configuration would lead to exceeding any implementation-specific limit,

    1.  *reject the graph*;

7.  If "the node" object has the `values` property:

    1.  *assert* that the `values` property is a non-empty JSON object;

    2.  for each property of the `values` JSON object:

        1.  *assert* that the property is a JSON object ("the input value socket");

        2.  if "the input value socket" object has the `node` property:

            1.  *assert* that "the input value socket" object does not have the `value` property;

            2.  *assert* that the `node` property is a JSON index;

            3.  if the `node` property value is not less than the index of the current element of the `nodes` array,

                1.  *reject the graph*;

            4.  let "the effective socket id" be `"value"`;

            5.  if "the input value socket" object has the `socket` property:

                1.  *assert* that the `socket` property is a JSON string;

                2.  set "the effective socket id" to the value of the `socket` property;

            6.  if the graph node referenced by the `node` property does not have the output value socket with id equal to "the effective socket id",

                1.  *reject the graph*;

            7.  if "the input value socket" object has the `type` property:

                1.  *assert* that the `type` property is a *JSON index*;

                2.  if the `type` property value is not less than the `types` graph array length,

                    1.  *reject the graph*;

                3.  if the type of the referenced output value socket does not match the type referenced by the `type` property value,

                    1.  *reject the graph*;

        3.  if "the input value socket" object does not have the `node` property:

            1.  *assert* that "the input value socket" object has the `type` property that is a *JSON index*;

            2.  if the `type` property value is not less than the `types` graph array length,

                1.  *reject the graph*;

            3.  if "the input value socket" object has the `value` property:

                1.  *assert* that the `value` property is a non-empty JSON array;

                2.  validate the `value` property value according to the [Inline Value Validation](#inline-value-validation) using the `type` property.

8.  Let "the operation inputs" be the set (or the sets in case of overloaded operations) of input value sockets defined by the declaration and/or derived from the configuration.

9.  If any input value socket id present in "the operation inputs" is not present in the set of input value sockets defined by the `values` property,

    1.  *reject the graph*.

10. If the types of input value sockets defined by the `values` property excluding sockets with ids not present in "the operation inputs" do not match any set of the input value socket types present in "the operation inputs",

    1.  *reject the graph*.

11. If "the node" object has the `flows` property:

    1.  *assert* that the `flows` property is a non-empty JSON object;

    2.  if the `flows` object has more properties than the implementation-specific limit on the number of output flow sockets per node,

        1.  *reject the graph*;

    3.  for each property of the `flows` JSON object:

        1.  *assert* that the property is a JSON object ("the output flow socket");

        2.  *assert* that "the output flow socket" object has the `node` property that is a JSON index;

        3.  if the `node` property value is not greater than the index of the current element of the `nodes` array,

            1.  *reject the graph*;

        4.  if "the output flow socket" object has the `socket` property,

            1.  *assert* that the `socket` property is a JSON string.

# Inline Value Object Validation 

1.  Let "the array" be the JSON array representing the inline value and "the type signature" be the type signature associated with it.

2.  If "the type signature" is `"bool"`, `"float"`, or `"int"` and "the array" length is not one,

    1.  *reject the graph*.

3.  If "the type signature" is `"float2"` and "the array" length is not two,

    1.  *reject the graph*.

4.  If "the type signature" is `"float3"` and "the array" length is not three,

    1.  *reject the graph*.

5.  If "the type signature" is `"float4"` or `"float2x2"` and "the array" length is not four,

    1.  *reject the graph*.

6.  If "the type signature" is `"float3x3"` and "the array" length is not nine,

    1.  *reject the graph*.

7.  If "the type signature" is `"float4x4"` and "the array" length is not 16,

    1.  *reject the graph*.

8.  If "the type signature" is `"bool"` and the only element of "the array" is not a JSON boolean,

    1.  *reject the graph*.

9.  If "the type signature" is `"int"` and the only element of "the array" is not exactly representable as a 32-bit signed integer,

    1.  *reject the graph*.

10. If "the type signature" is any of the seven float types defined in this Specification and any element of "the array" is not a JSON number,

    1.  *reject the graph*.
