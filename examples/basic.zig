//! Basic nanoarrow usage from Zig. Doubles as the smoke test: `zig build test`.
const std = @import("std");
const na = @import("nanoarrow");

fn check(code: na.ArrowErrorCode) !void {
    if (code != na.NANOARROW_OK) return error.NanoarrowError;
}

test "library and header versions agree" {
    try std.testing.expectEqualStrings(na.NANOARROW_VERSION, std.mem.span(na.ArrowNanoarrowVersion()));
}

test "build an int32 array with a null and read it back" {
    var schema: na.ArrowSchema = undefined;
    try check(na.ArrowSchemaInitFromType(&schema, na.NANOARROW_TYPE_INT32));
    defer schema.release.?(&schema);
    try check(na.ArrowSchemaSetName(&schema, "ints"));

    var array: na.ArrowArray = undefined;
    try check(na.ArrowArrayInitFromSchema(&array, &schema, null));
    defer array.release.?(&array);

    try check(na.ArrowArrayStartAppending(&array));
    for (0..5) |i| try check(na.ArrowArrayAppendInt(&array, @as(i64, @intCast(i)) * 10));
    try check(na.ArrowArrayAppendNull(&array, 1));
    try check(na.ArrowArrayFinishBuildingDefault(&array, null));

    try std.testing.expectEqual(@as(i64, 6), array.length);
    try std.testing.expectEqual(@as(i64, 1), array.null_count);

    var view: na.ArrowArrayView = undefined;
    try check(na.ArrowArrayViewInitFromSchema(&view, &schema, null));
    defer na.ArrowArrayViewReset(&view);
    try check(na.ArrowArrayViewSetArray(&view, &array, null));

    try std.testing.expectEqual(@as(i64, 30), na.ArrowArrayViewGetIntUnsafe(&view, 3));
    try std.testing.expect(na.ArrowArrayViewIsNull(&view, 5) != 0);
}

test "build a double array" {
    var array: na.ArrowArray = undefined;
    try check(na.ArrowArrayInitFromType(&array, na.NANOARROW_TYPE_DOUBLE));
    defer array.release.?(&array);

    try check(na.ArrowArrayStartAppending(&array));
    try check(na.ArrowArrayAppendDouble(&array, 1.5));
    try check(na.ArrowArrayAppendDouble(&array, 2.5));
    try check(na.ArrowArrayFinishBuildingDefault(&array, null));

    try std.testing.expectEqual(@as(i64, 2), array.length);
}
