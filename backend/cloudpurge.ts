export type EncryptedMessageRecord = {
  id: string;
  senderId: string;
  createdAt: number;
};

export type CloudPurgeReceipt = {
  messageId: string;
  senderId: string;
  receiverId: string;
  createdAt: number;
  purgedAt: number;
  reason: "cloudpurge-received";
};

export function createCloudPurgeReceipt(
  message: EncryptedMessageRecord,
  receiverId: string,
  purgedAt: number,
): CloudPurgeReceipt {
  if (!message.id || !message.senderId || !receiverId) {
    throw new Error("A message, sender, and receiver are required.");
  }
  if (receiverId === message.senderId) {
    throw new Error("The sender cannot acknowledge their own message.");
  }
  if (!Number.isSafeInteger(purgedAt) || purgedAt <= 0) {
    throw new Error("A valid server timestamp is required.");
  }
  return {
    messageId: message.id,
    senderId: message.senderId,
    receiverId,
    createdAt: message.createdAt,
    purgedAt,
    reason: "cloudpurge-received",
  };
}

export function isCloudPurgeReceiptFor(
  receipt: unknown,
  receiverId: string,
): receipt is CloudPurgeReceipt {
  if (!receipt || typeof receipt !== "object") return false;
  const value = receipt as Record<string, unknown>;
  return value.reason === "cloudpurge-received" &&
    value.receiverId === receiverId &&
    typeof value.messageId === "string" &&
    typeof value.senderId === "string";
}
