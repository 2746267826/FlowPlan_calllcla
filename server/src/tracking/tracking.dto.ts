import { IsString, IsOptional, IsNumber, IsArray } from 'class-validator';
export class CreateBatchDto {
  @IsOptional() @IsString() batchUid?: string;
  @IsOptional() @IsString() dataKind?: string;
  @IsOptional() @IsString() compression?: string;
  @IsOptional() @IsString() payloadHash?: string;
  @IsOptional() @IsString() startAt?: string;
  @IsOptional() @IsString() endAt?: string;
  @IsOptional() @IsArray() records?: unknown[];
  @IsOptional() metadata?: Record<string, unknown>;
}
export class AppendChunkDto {
  @IsNumber() chunkIndex!: number;
  @IsOptional() payload?: Record<string, unknown>;
  @IsOptional() @IsString() payloadBase64?: string;
  @IsOptional() @IsString() checksum?: string;
}
export class CompleteBatchDto {
  @IsOptional() @IsArray() records?: unknown[];
}
