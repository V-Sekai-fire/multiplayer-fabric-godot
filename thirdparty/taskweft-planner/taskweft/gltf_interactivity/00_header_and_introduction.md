# glTF™ 2.0 Interactivity Extension Specification

[The Khronos® 3D Formats Working Group]

Table of Contents

- [1. Foreword](#foreword)
- [2. Introduction](#introduction)
  - [2.1. General](#introduction-general)
  - [2.2. Document Conventions](#introduction-conventions)
    - [2.2.1. Normative Terminology and References](#introduction-normative-terminology)
    - [2.2.2. Informative Language](#introduction-informative-language)
    - [2.2.3. Technical Terminology](#introduction-technical-terminology)
    - [2.2.4. Normative References](#introduction-normative-references)
      - [2.2.4.1. External Specifications](#_external_specifications)
  - [2.3. Motivation and Design Goals (Informative)](#motivation)
    - [2.3.1. What Is a Behavior Graph?](#_what_is_a_behavior_graph)
    - [2.3.2. What Problems Can They Solve?](#_what_problems_can_they_solve)
    - [2.3.3. What Do They Not Solve?](#_what_do_they_not_solve)
    - [2.3.4. Comparison with Trigger-Action Lists](#_comparison_with_trigger_action_lists)
    - [2.3.5. Turing Completeness](#_turing_completeness)
- [3. Concepts](#concepts)

## 1. Foreword

Copyright 2024 The Khronos Group Inc.

This specification is protected by copyright laws and contains material proprietary to Khronos. Except as described by these terms, it or any components may not be reproduced, republished, distributed, transmitted, displayed, broadcast, or otherwise exploited in any manner without the express prior written permission of Khronos.

This specification has been created under the Khronos Intellectual Property Rights Policy, which is Attachment A of the Khronos Group Membership Agreement available at [https://www.khronos.org/files/member_agreement.pdf](https://www.khronos.org/files/member_agreement.pdf). Khronos grants a conditional copyright license to use and reproduce the unmodified specification for any purpose, without fee or royalty, EXCEPT no licenses to any patent, trademark or other intellectual property rights are granted under these terms. Parties desiring to implement the specification and make use of Khronos trademarks in relation to that implementation, and receive reciprocal patent license protection under the Khronos IP Policy must become Adopters under the process defined by Khronos for this specification; see [https://www.khronos.org/conformance/adopters/file-format-adopter-program](https://www.khronos.org/conformance/adopters/file-format-adopter-program).

Some parts of this Specification are non-normative through being explicitly identified as purely informative, and do not define requirements necessary for compliance and so are outside the Scope of this Specification.

Where this Specification includes normative references to external documents, only the specifically identified sections and functionality of those external documents are in Scope. Requirements defined by external documents not created by Khronos may contain contributions from non-members of Khronos not covered by the Khronos Intellectual Property Rights Policy.

Khronos makes no, and expressly disclaims any, representations or warranties, express or implied, regarding this specification, including, without limitation: merchantability, fitness for a particular purpose, non-infringement of any intellectual property, correctness, accuracy, completeness, timeliness, and reliability. Under no circumstances will Khronos, or any of its Promoters, Contributors or Members, or their respective partners, officers, directors, employees, agents or representatives be liable for any damages, whether direct, indirect, special or consequential damages for lost revenues, lost profits, or otherwise, arising from or in connection with these materials.

Khronos® and Vulkan® are registered trademarks, and ANARI™, WebGL™, glTF™, NNEF™, OpenVX™, SPIR™, SPIR‑V™, SYCL™, OpenVG™ and 3D Commerce™ are trademarks of The Khronos Group Inc. OpenXR™ is a trademark owned by The Khronos Group Inc. and is registered as a trademark in China, the European Union, Japan and the United Kingdom. OpenCL™ is a trademark of Apple Inc. and OpenGL® is a registered trademark and the OpenGL ES™ and OpenGL SC™ logos are trademarks of Hewlett Packard Enterprise used under license by Khronos. ASTC is a trademark of ARM Holdings PLC. All other product names, trademarks, and/or company names are used solely for identification and belong to their respective owners.

## 2. Introduction

### 2.1. General 

This document, referred to as the "glTF Interactivity Extension Specification" or just the "Specification" hereafter, describes the `KHR_interactivity` glTF extension.

This extension aims to enhance glTF 2.0 by adding the ability to encode behavior and interactivity in 3D assets.

This extension is for single user experiences only and does not deal with any of the complexity involved in multi-user networked experiences.

### 2.2. Document Conventions 

The glTF Interactivity Extension Specification is intended for use by both implementers of the asset exporters or converters (e.g., digital content creation tools) and application developers seeking to import or load interactive glTF assets, forming a basis for interoperability between these parties.

Specification text can address either party; typically, the intended audience can be inferred from context, though some sections are defined to address only one of these parties.

Any requirements, prohibitions, recommendations, or options defined by [normative terminology](#introduction-normative-terminology) are imposed only on the audience of that text.

#### 2.2.1. Normative Terminology and References 

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in [BCP 14](#bcp14).

These key words are highlighted in the specification for clarity.

References to external documents are considered normative if the Specification uses any of the normative terms defined in this section to refer to them or their requirements, either as a whole or in part.

#### 2.2.2. Informative Language 

Some language in the specification is purely informative, intended to give background or suggestions to implementers or developers.

If an entire chapter or section contains only informative language, its title is suffixed with "(Informative)". If not designated as informative, all chapters, sections, and appendices in this document are normative.

All Notes, Implementation notes, and Examples are purely informative.

#### 2.2.3. Technical Terminology 

TBD

#### 2.2.4. Normative References 

The following documents are referenced by normative sections of the specification:

##### 2.2.4.1. External Specifications 

- [] Bradner, S., *Key words for use in RFCs to Indicate Requirement Levels*, BCP 14, RFC 2119, DOI 10.17487/RFC2119, March 1997. Leiba, B., *Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words*, BCP 14, RFC 8174, DOI 10.17487/RFC8174, May 2017. [https://www.rfc-editor.org/info/bcp14](https://www.rfc-editor.org/info/bcp14)

- [] Bryan, P., Ed., Zyp, K., and M. Nottingham, Ed., *JavaScript Object Notation (JSON) Pointer*, RFC 6901, DOI 10.17487/RFC6901, April 2013, [https://www.rfc-editor.org/info/rfc6901](https://www.rfc-editor.org/info/rfc6901)

- [] ISO/IEC 60559 *Floating-point arithmetic* [https://www.iso.org/standard/80985.html](https://www.iso.org/standard/80985.html)

  +-----------------------------------+----------------------------------------------------------------------------------------------------------------------------+
  |                                   | ::: paragraph                                                                                                              |
  |                                   | Also known as IEEE 754-2019, [https://standards.ieee.org/ieee/754/6210/](https://standards.ieee.org/ieee/754/6210/) |
  |                                   | :::                                                                                                                        |
  +-----------------------------------+----------------------------------------------------------------------------------------------------------------------------+

- [] ECMA-262 *ECMAScript® Language Specification* [https://www.ecma-international.org/publications-and-standards/standards/ecma-262/](https://www.ecma-international.org/publications-and-standards/standards/ecma-262/)

### 2.3. Motivation and Design Goals (Informative) 

glTF 2.0 assets are widely used in various industries, including automotive, e-commerce, and gaming. There is a growing demand for adding logic and behavior to glTF assets, particularly in the metaverse. This extension aims to fulfill this demand by providing a portable, easily implementable, safe, and visually accessible solution for adding behavior to glTF assets. The extension is inspired by visual scripting features of leading game engines and aims to deliver a minimum meaningful and extensible feature set.

#### 2.3.1. What Is a Behavior Graph? 

A behavior graph is a series of interconnected nodes that represent behaviors and interactions in a 3D asset. It can respond to events and cause changes in the asset's appearance and behavior.

#### 2.3.2. What Problems Can They Solve? 

Behavior graphs offer a flexible and multi-functional approach to encoding behavior, making them useful for various applications. For instance, they can be used to create smart assets with behavior and interactions, AR experiences with user interactions, and immersive game levels with dynamic assets and objectives.

#### 2.3.3. What Do They Not Solve? 

Behavior graphs are not designed to handle UI presentation or arbitrary scripting. Creating a 3D UI using behavior graphs would be complex, not portable, and not accessible. Similarly, arbitrary scripting is challenging to make safe, portable across platforms, and has a vast surface area.

#### 2.3.4. Comparison with Trigger-Action Lists 

Behavior graphs and trigger-action lists are the two common models for representing and executing behaviors in the digital world. Common 3D experience commerce tools use trigger-action lists, while behavior graphs are typically used by high-end game engines. In this section, we will explore the differences and similarities between these two models, and explain why glTF chose to adopt behavior graphs.

Behavior graphs and trigger-action lists share common features, such as being safe and sandboxed, offering limited execution models controlled by the viewer, and both supporting the "trigger" and "action" node categories. However, there are also significant differences between the two models. Trigger-action lists lack "Queries", "Logic", and "Control Flow" nodes, meaning that sophisticated behavior based on queries, logic, or control flow branches is not possible. This lack of functionality greatly affects the ability to create complex behavior and control structures and rules out the implementation of advanced control flow structures in the future.

On the other hand, behavior graphs are a superset of trigger-action lists, meaning that the former can support everything that trigger-action lists can, and more. Behavior graphs support "Queries", "Logic" and "Control Flow" nodes, making them more expressive and capable of creating more sophisticated behaviors. This makes behavior graphs the preferred method of choice for high-end game engines, as it offers an identical safety model as trigger-action lists while being more expressive.

#### 2.3.5. Turing Completeness 

The execution model and operation choices for this extension mean that it is Turing-complete. This means that an implementation of this can execute any computation and it is not always possible to predict if it will run forever, e.g., halt or not.

While this may present security implications, it is not a major hindrance and can be safely mitigated so that any implementation does not become susceptible to denial of services by badly behaving behavior graphs, whether intentional or not.

The main way to mitigate the risk of non-halting behavior graphs is to limit the amount of time given to them for execution, both in terms of individual time slice as well as overall execution time.

## 3. Concepts

Last updated 2026-01-01 17:23:19 -0800
