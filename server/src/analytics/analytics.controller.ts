import { Controller, Get, Headers, Query } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { AnalyticsService, AnalyticsQuery } from './analytics.service';

@Controller('analytics')
export class AnalyticsController {
  constructor(private readonly analyticsService: AnalyticsService) {}

  @Get('activity-heatmap')
  activityHeatmap(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.activityHeatmap(
      query,
      readRequestContext(headers),
    );
  }

  @Get('input-heatmap')
  inputHeatmap(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.inputHeatmap(query, readRequestContext(headers));
  }

  @Get('activity-range-summary')
  activityRangeSummary(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.activityRangeSummary(
      query,
      readRequestContext(headers),
    );
  }

  @Get('top-apps')
  topApps(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.topApps(query, readRequestContext(headers));
  }

  @Get('top-categories')
  topCategories(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.topCategories(
      query,
      readRequestContext(headers),
    );
  }

  @Get('task-work-summary')
  taskWorkSummary(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.taskWorkSummary(
      query,
      readRequestContext(headers),
    );
  }

  @Get('focus-trends')
  focusTrends(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.focusTrends(query, readRequestContext(headers));
  }

  @Get('activity-records')
  activityRecords(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.activityRecords(
      query,
      readRequestContext(headers),
    );
  }

  @Get('input-events')
  inputEvents(
    @Query() query: AnalyticsQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.analyticsService.inputEvents(query, readRequestContext(headers));
  }
}
