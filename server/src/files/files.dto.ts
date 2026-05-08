import { IsString, IsOptional, IsNumber } from 'class-validator';
export class UploadChunkDto {
  @IsString() sessionId!: string;
  @IsNumber() chunkIndex!: number;
  @IsOptional() @IsString() payloadBase64?: string;
  @IsOptional() @IsString() checksum?: string;
}
export class CreateDownloadSessionDto {
  @IsString() fileId!: string;
  @IsOptional() @IsString() format?: string;
}
export class SharedDownloadDto {
  @IsString() path!: string;
  @IsOptional() @IsNumber() start?: number;
  @IsOptional() @IsNumber() end?: number;
}
