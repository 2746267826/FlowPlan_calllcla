import { IsString, IsOptional, IsUUID } from 'class-validator';

export class LoginDto {
  @IsOptional()
  @IsUUID()
  userId?: string;

  @IsOptional()
  @IsString()
  displayName?: string;
}

export class RefreshDto {
  @IsString()
  refreshToken!: string;
}

export class LogoutDto {
  @IsOptional()
  @IsString()
  refreshToken?: string;
}
