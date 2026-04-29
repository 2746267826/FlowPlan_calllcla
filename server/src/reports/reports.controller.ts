import { Body, Controller, Get, Headers, Param, Patch, Post, Query } from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { ReportsQuery, ReportsService } from './reports.service';

@Controller()
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get('reports')
  reports(@Query() query: ReportsQuery, @Headers() headers: Record<string, unknown>) {
    return this.reportsService.reports(query, readRequestContext(headers));
  }

  @Get('reports/:reportId')
  report(@Param('reportId') reportId: string, @Headers() headers: Record<string, unknown>) {
    return this.reportsService.report(reportId, readRequestContext(headers));
  }

  @Post('reports/generate')
  generateReport(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.generateReport(body, readRequestContext(headers));
  }

  @Patch('reports/:reportId')
  updateReport(
    @Param('reportId') reportId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.updateReport(reportId, body, readRequestContext(headers));
  }

  @Post('reports/:reportId/confirm')
  confirmReport(
    @Param('reportId') reportId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.confirmReport(reportId, readRequestContext(headers));
  }

  @Post('reports/:reportId/polish')
  polishReport(
    @Param('reportId') reportId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.polishReport(reportId, readRequestContext(headers));
  }

  @Post('reports/:reportId/push')
  pushReport(
    @Param('reportId') reportId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.pushReport(reportId, body, readRequestContext(headers));
  }

  @Get('diary')
  diary(@Query() query: ReportsQuery, @Headers() headers: Record<string, unknown>) {
    return this.reportsService.diary(query, readRequestContext(headers));
  }

  @Post('diary/generate')
  generateDiary(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.generateDiary(body, readRequestContext(headers));
  }

  @Patch('diary/:diaryId')
  updateDiary(
    @Param('diaryId') diaryId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.updateDiary(diaryId, body, readRequestContext(headers));
  }

  @Post('diary/:diaryId/confirm')
  confirmDiary(
    @Param('diaryId') diaryId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.confirmDiary(diaryId, readRequestContext(headers));
  }

  @Post('diary/:diaryId/polish')
  polishDiary(
    @Param('diaryId') diaryId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.polishDiary(diaryId, readRequestContext(headers));
  }

  @Get('report-templates')
  templates(@Headers() headers: Record<string, unknown>) {
    return this.reportsService.templates(readRequestContext(headers));
  }

  @Post('report-templates')
  upsertTemplate(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.upsertTemplate(body, readRequestContext(headers));
  }

  @Get('push/channels')
  pushChannels(@Headers() headers: Record<string, unknown>) {
    return this.reportsService.pushChannels(readRequestContext(headers));
  }

  @Post('push/channels')
  upsertPushChannel(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.upsertPushChannel(body, readRequestContext(headers));
  }

  @Get('push/deliveries')
  pushDeliveries(@Query() query: ReportsQuery, @Headers() headers: Record<string, unknown>) {
    return this.reportsService.pushDeliveries(query, readRequestContext(headers));
  }

  @Post('push/deliveries/:deliveryId/retry')
  retryDelivery(
    @Param('deliveryId') deliveryId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.retryDelivery(deliveryId, readRequestContext(headers));
  }

  @Get('weather/locations')
  weatherLocations(@Headers() headers: Record<string, unknown>) {
    return this.reportsService.weatherLocations(readRequestContext(headers));
  }

  @Post('weather/locations')
  upsertWeatherLocation(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.upsertWeatherLocation(body, readRequestContext(headers));
  }

  @Post('weather/locations/:locationId/refresh')
  refreshWeather(
    @Param('locationId') locationId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.reportsService.refreshWeather(locationId, readRequestContext(headers));
  }

  @Get('weather/summary')
  weatherSummary(@Query() query: ReportsQuery, @Headers() headers: Record<string, unknown>) {
    return this.reportsService.weatherSummary(query, readRequestContext(headers));
  }
}
