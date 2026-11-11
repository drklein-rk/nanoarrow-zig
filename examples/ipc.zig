//! Arrow IPC round trip from Zig: write a record batch to an in-memory stream and read it back.
//! Requires `-Dipc`: `zig build test -Dipc`.
const std = @import("std");
const na = @import("nanoarrow_ipc");

fn check(code: na.ArrowErrorCode) !void {
    if (code != na.NANOARROW_OK) return error.NanoarrowError;
}

test "write and read an IPC stream" {
    // Schema: struct<ints: int32>
    var schema: na.ArrowSchema = undefined;
    try check(na.ArrowSchemaInitFromType(&schema, na.NANOARROW_TYPE_STRUCT));
    defer schema.release.?(&schema);
    try check(na.ArrowSchemaAllocateChildren(&schema, 1));
    try check(na.ArrowSchemaInitFromType(schema.children[0], na.NANOARROW_TYPE_INT32));
    try check(na.ArrowSchemaSetName(schema.children[0], "ints"));

    var array: na.ArrowArray = undefined;
    try check(na.ArrowArrayInitFromSchema(&array, &schema, null));
    defer array.release.?(&array);
    try check(na.ArrowArrayStartAppending(&array));
    const ints = array.children[0];
    for (0..4) |i| {
        try check(na.ArrowArrayAppendInt(ints, @as(i64, @intCast(i)) * 10));
        try check(na.ArrowArrayFinishElement(&array));
    }
    try check(na.ArrowArrayAppendNull(ints, 1));
    try check(na.ArrowArrayFinishElement(&array));
    try check(na.ArrowArrayFinishBuildingDefault(&array, null));

    var view: na.ArrowArrayView = undefined;
    try check(na.ArrowArrayViewInitFromSchema(&view, &schema, null));
    defer na.ArrowArrayViewReset(&view);
    try check(na.ArrowArrayViewSetArray(&view, &array, null));

    // Write schema and batch into a buffer.
    var buffer: na.ArrowBuffer = undefined;
    na.ArrowBufferInit(&buffer);
    var buffer_owned = true;
    defer if (buffer_owned) na.ArrowBufferReset(&buffer);

    {
        var output: na.ArrowIpcOutputStream = undefined;
        try check(na.ArrowIpcOutputStreamInitBuffer(&output, &buffer));
        var writer: na.ArrowIpcWriter = undefined;
        try check(na.ArrowIpcWriterInit(&writer, &output)); // takes ownership of output
        defer na.ArrowIpcWriterReset(&writer);

        var err: na.ArrowError = undefined;
        try check(na.ArrowIpcWriterWriteSchema(&writer, &schema, &err));
        try check(na.ArrowIpcWriterWriteArrayView(&writer, &view, &err));
    }
    try std.testing.expect(buffer.size_bytes > 0);

    // Read it back; the input stream takes ownership of the buffer.
    var input: na.ArrowIpcInputStream = undefined;
    try check(na.ArrowIpcInputStreamInitBuffer(&input, &buffer));
    buffer_owned = false;

    var stream: na.ArrowArrayStream = undefined;
    try check(na.ArrowIpcArrayStreamReaderInit(&stream, &input, null));
    defer stream.release.?(&stream);

    var read_schema: na.ArrowSchema = undefined;
    try std.testing.expectEqual(@as(c_int, 0), stream.get_schema.?(&stream, &read_schema));
    defer read_schema.release.?(&read_schema);
    try std.testing.expectEqual(@as(i64, 1), read_schema.n_children);

    var read_array: na.ArrowArray = undefined;
    try std.testing.expectEqual(@as(c_int, 0), stream.get_next.?(&stream, &read_array));
    defer read_array.release.?(&read_array);
    try std.testing.expectEqual(@as(i64, 5), read_array.length);

    var read_view: na.ArrowArrayView = undefined;
    try check(na.ArrowArrayViewInitFromSchema(&read_view, &read_schema, null));
    defer na.ArrowArrayViewReset(&read_view);
    try check(na.ArrowArrayViewSetArray(&read_view, &read_array, null));

    const col = read_view.children[0];
    try std.testing.expectEqual(@as(i64, 20), na.ArrowArrayViewGetIntUnsafe(col, 2));
    try std.testing.expect(na.ArrowArrayViewIsNull(col, 4) != 0);
}
