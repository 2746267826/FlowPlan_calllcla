import { IsString, IsOptional, IsBoolean } from 'class-validator';
export class GenerateReportDto {
  @IsString() reportType!: string;
  @IsOptional() @IsString() date?: string;
  @IsOptional() @IsString() start?: string;
  @IsOptional() @IsString() end?: string;
  @IsOptional() @IsBoolean() useLlm?: boolean;
  @IsOptional() @IsString() locationId?: string;
}
export class PolishReportDto {
  @IsOptional() @IsString() prompt?: string;
}
