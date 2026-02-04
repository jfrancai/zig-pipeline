# zig-pipe

Sandbox code exploring functional pipelines in Zig.

## Example

```zig
PipelineBuilder.from(&allocator, &arr)
    .filter(odd())
    .map(.{ add(1), add(2) })
    .take(3)
    .collect();
```

## Run

```sh
zig run main.zig
```

Not a library. Just an experiment with Zig's compile-time features.
