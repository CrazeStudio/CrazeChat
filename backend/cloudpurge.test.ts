import assert from "node:assert/strict";
import test from "node:test";
import {
  createCloudPurgeReceipt,
  isCloudPurgeReceiptFor,
} from "./cloudpurge.js";

test("receiver acknowledgement creates a server-timestamped tombstone", () => {
  const receipt = createCloudPurgeReceipt(
    { id: "a".repeat(32), senderId: "alice", createdAt: 100 },
    "bob",
    200,
  );
  assert.deepEqual(receipt, {
    messageId: "a".repeat(32),
    senderId: "alice",
    receiverId: "bob",
    createdAt: 100,
    purgedAt: 200,
    reason: "cloudpurge-received",
  });
  assert.equal(isCloudPurgeReceiptFor(receipt, "bob"), true);
  assert.equal(isCloudPurgeReceiptFor(receipt, "alice"), false);
});

test("sender cannot acknowledge their own message", () => {
  assert.throws(
    () => createCloudPurgeReceipt(
      { id: "b".repeat(32), senderId: "alice", createdAt: 100 },
      "alice",
      200,
    ),
    /sender cannot acknowledge/i,
  );
});

test("invalid server timestamps are rejected", () => {
  assert.throws(
    () => createCloudPurgeReceipt(
      { id: "c".repeat(32), senderId: "alice", createdAt: 100 },
      "bob",
      0,
    ),
    /timestamp/i,
  );
});
