import { Controller, Get, Param, Post } from '@nestjs/common';
import { CronJobsService } from './cron-jobs.service';

@Controller('admin/jobs')
export class CronJobsController {
  constructor(private readonly cronJobsService: CronJobsService) {}

  @Get()
  listJobs() {
    return { jobs: this.cronJobsService.listJobs() };
  }

  @Post(':jobName/trigger')
  triggerJob(@Param('jobName') jobName: string) {
    return this.cronJobsService.triggerJob(jobName);
  }

  @Post(':jobName/pause')
  pauseJob(@Param('jobName') jobName: string) {
    return this.cronJobsService.pauseJob(jobName);
  }

  @Post(':jobName/resume')
  resumeJob(@Param('jobName') jobName: string) {
    return this.cronJobsService.resumeJob(jobName);
  }
}
