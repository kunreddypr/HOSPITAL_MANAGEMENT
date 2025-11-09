import { randomUUID } from 'crypto';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const region = process.env.AWS_REGION ?? 'eu-west-3';

export const s3Client = new S3Client({ region });
export const dynamoClient = new DynamoDBClient({ region });

export async function createPresignedUploadUrl(
  bucket: string,
  key: string,
  options?: { expiresInSeconds?: number; contentType?: string }
) {
  const command = new PutObjectCommand({
    Bucket: bucket,
    Key: key,
    ContentType: options?.contentType
  });
  return getSignedUrl(s3Client, command, { expiresIn: options?.expiresInSeconds ?? 3600 });
}

export async function writeAuditLog(tableName: string, payload: Record<string, string>) {
  const item = Object.entries(payload).reduce<Record<string, { S: string }>>((acc, [key, value]) => {
    acc[key] = { S: value };
    return acc;
  }, {});

  const command = new PutItemCommand({
    TableName: tableName,
    Item: {
      ...item,
      id: { S: randomUUID() },
      createdAt: { S: new Date().toISOString() }
    }
  });

  await dynamoClient.send(command);
}
