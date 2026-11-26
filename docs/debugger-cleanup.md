# Script diagnostics cleanup

Godot 4.7's language server initially reported 49 warnings across the 88 game scripts. These were shadowed local/parameter names, confusing declarations in nested scopes, mixed types in conditional expressions and implicit integer division. The cleanup gives locals distinct names, casts camera/pilot alternatives to their shared Node3D type, uses floating-point branches consistently and makes integer truncation explicit. Runtime dictionary fields and identifiers in saved data retain their names; game settings and balance remain unchanged.

The same diagnostics scan now reports zero warnings or errors for those 88 scripts. The component test's generated UID is tracked to avoid the recurring missing-UID import warning. The dormant hyper-gate test now measures its terminal gap in authored map units, retaining its original tolerance when the system's world-space scale changes.

Validation uses Godot 4.7: all 23 Artois smoke suites, market transactions, benchmark navigation, the Pilgrim model and classic component smoke tests. An actual scene launch also completes using the cloud machine's OpenGL fallback. This machine lacks the Vulkan surface extension and cannot validate Forward+ rendering; its driver fallback and VSync warnings are separate from script diagnostics. The project renderer has not been changed.

The user's local debugger messages were not available during this pass, so this does not establish that these warnings are the same as their reported 33 errors. Any remaining red errors should be matched using the original message and stack trace.
