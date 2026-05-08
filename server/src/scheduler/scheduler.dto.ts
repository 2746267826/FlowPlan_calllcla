import { IsString, IsOptional, IsNumber, IsArray, IsObject } from 'class-validator';
export class CreateRunDto {
  @IsString() rangeStart!: string;
  @IsString() rangeEnd!: string;
  @IsOptional() @IsNumber() defaultTaskMinutes?: number;
  @IsOptional() @IsString() strategy?: string;
  @IsOptional() @IsString() mode?: string;
}
export class GeneticEvolveDto {
  @IsArray() tasks!: unknown[];
  @IsArray() freeSlots!: unknown[];
  @IsArray() topoOrder!: string[];
  @IsOptional() @IsObject() config?: Record<string, number>;
  @IsOptional() @IsObject() userScores?: Record<string, number>;
}
export class TopoSortDto {
  @IsArray() tasks!: unknown[];
}
