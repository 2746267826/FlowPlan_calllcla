import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Patch,
  Post,
  Put,
  Query,
} from '@nestjs/common';
import { readRequestContext } from '../common/request-context';
import { FilesQuery, FilesService } from './files.service';

@Controller('files')
export class FilesController {
  constructor(private readonly filesService: FilesService) {}

  @Get('providers')
  providers(@Headers() headers: Record<string, unknown>) {
    return this.filesService.providers(readRequestContext(headers));
  }

  @Get('dashboard')
  dashboard(@Headers() headers: Record<string, unknown>) {
    return this.filesService.dashboard(readRequestContext(headers));
  }

  @Patch('providers/:providerKey')
  upsertProvider(
    @Param('providerKey') providerKey: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.upsertProvider(
      providerKey,
      body,
      readRequestContext(headers),
    );
  }

  @Post('tree/snapshot')
  applyTreeSnapshot(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.applyTreeSnapshot(body, readRequestContext(headers));
  }

  @Get('tree')
  tree(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.tree(query, readRequestContext(headers));
  }

  @Get('roots')
  roots(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.roots(query, readRequestContext(headers));
  }

  @Get('drive/roots')
  driveRoots(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.driveRoots(query, readRequestContext(headers));
  }

  @Post('roots')
  upsertRoot(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.upsertRoot(body, readRequestContext(headers));
  }

  @Get('nodes')
  fileNodes(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.fileNodes(query, readRequestContext(headers));
  }

  @Get('drive/nodes')
  driveNodes(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.driveNodes(query, readRequestContext(headers));
  }

  @Get('drive/nodes/:nodeId')
  driveNode(
    @Param('nodeId') nodeId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.driveNode(nodeId, readRequestContext(headers));
  }

  @Post('drive/nodes/:nodeId/open-plan')
  driveOpenPlan(
    @Param('nodeId') nodeId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.driveOpenPlan(
      nodeId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('drive/nodes/:nodeId/device-location')
  upsertDriveDeviceLocation(
    @Param('nodeId') nodeId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.upsertDriveDeviceLocation(
      nodeId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('drive/nodes/:nodeId/download-request')
  createDriveDownloadRequest(
    @Param('nodeId') nodeId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.createDriveDownloadRequest(
      nodeId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('drive/roots/:rootId/scan')
  scanDriveRoot(
    @Param('rootId') rootId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.scanDriveRoot(
      rootId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('drive/nodes/:nodeId/relink')
  relinkDriveNode(
    @Param('nodeId') nodeId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.relinkDriveNode(
      nodeId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('nodes/snapshot')
  applyNodeSnapshot(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.applyNodeSnapshot(body, readRequestContext(headers));
  }

  @Post('nodes/:nodeId/log')
  logNodeOperation(
    @Param('nodeId') nodeId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.logNodeOperation(
      nodeId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('context-links')
  linkNodeToEntity(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.linkNodeToEntity(body, readRequestContext(headers));
  }

  @Get('context-links')
  contextLinks(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.contextLinks(query, readRequestContext(headers));
  }

  @Get('recommendations')
  recommendations(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.recommendations(query, readRequestContext(headers));
  }

  @Post('recommendations/:recommendationId/review')
  reviewRecommendation(
    @Param('recommendationId') recommendationId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.reviewRecommendation(
      recommendationId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('upload-sessions')
  createUploadSession(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.createUploadSession(body, readRequestContext(headers));
  }

  @Post('transfers/upload-session')
  createUploadTransferSession(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.createUploadSession(body, readRequestContext(headers));
  }

  @Put('upload-sessions/:sessionId/chunks/:chunkIndex')
  uploadChunk(
    @Param('sessionId') sessionId: string,
    @Param('chunkIndex') chunkIndex: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.uploadChunk(
      sessionId,
      chunkIndex,
      body,
      readRequestContext(headers),
    );
  }

  @Post('transfers/:sessionId/chunks/:chunkIndex')
  uploadTransferChunk(
    @Param('sessionId') sessionId: string,
    @Param('chunkIndex') chunkIndex: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.uploadChunk(
      sessionId,
      chunkIndex,
      body,
      readRequestContext(headers),
    );
  }

  @Get('upload-sessions/:sessionId/missing-chunks')
  missingUploadChunks(
    @Param('sessionId') sessionId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.missingUploadChunks(
      sessionId,
      readRequestContext(headers),
    );
  }

  @Get('transfers/:sessionId/missing-chunks')
  missingTransferUploadChunks(
    @Param('sessionId') sessionId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.missingUploadChunks(
      sessionId,
      readRequestContext(headers),
    );
  }

  @Post('upload-sessions/:sessionId/complete')
  completeUploadSession(
    @Param('sessionId') sessionId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.completeUploadSession(
      sessionId,
      readRequestContext(headers),
    );
  }

  @Post('transfers/:sessionId/complete')
  completeUploadTransferSession(
    @Param('sessionId') sessionId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.completeUploadSession(
      sessionId,
      readRequestContext(headers),
    );
  }

  @Post('download-sessions')
  createDownloadSession(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.createDownloadSession(
      body,
      readRequestContext(headers),
    );
  }

  @Get('download-sessions/:sessionId/range')
  downloadRange(
    @Param('sessionId') sessionId: string,
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.downloadRange(
      sessionId,
      query,
      readRequestContext(headers),
    );
  }

  @Get('storage/:objectId/download')
  downloadStorageObject(
    @Param('objectId') objectId: string,
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.downloadStorageObject(
      objectId,
      query,
      readRequestContext(headers),
    );
  }

  @Get('transfers')
  transfers(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.transfers(query, readRequestContext(headers));
  }

  @Get('transfers/:sessionId/progress')
  transferProgress(
    @Param('sessionId') sessionId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.transferProgress(
      sessionId,
      readRequestContext(headers),
    );
  }

  @Post('network-presence')
  upsertNetworkPresence(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.upsertNetworkPresence(
      body,
      readRequestContext(headers),
    );
  }

  @Get('network-presence')
  networkPresence(@Headers() headers: Record<string, unknown>) {
    return this.filesService.networkPresence(readRequestContext(headers));
  }

  @Get('transfers/:sessionId/candidates')
  transferCandidates(
    @Param('sessionId') sessionId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.transferCandidates(
      sessionId,
      readRequestContext(headers),
    );
  }

  @Post('transfers/:sessionId/candidates')
  upsertTransferCandidate(
    @Param('sessionId') sessionId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.upsertTransferCandidate(
      sessionId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('transfers/:sessionId/events')
  appendTransferEvent(
    @Param('sessionId') sessionId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.appendTransferEvent(
      sessionId,
      body,
      readRequestContext(headers),
    );
  }

  @Get('storage/status')
  storageStatus() {
    return this.filesService.storageStatus();
  }

  @Get('storage/objects')
  storageObjects(
    @Query() query: FilesQuery,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.storageObjects(query, readRequestContext(headers));
  }

  @Post('storage/register')
  registerStorageObject(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.registerStorageObject(
      body,
      readRequestContext(headers),
    );
  }

  @Post('kopia/snapshots')
  createKopiaSnapshot(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.createKopiaSnapshot(body, readRequestContext(headers));
  }

  @Post('kopia/versions/refresh')
  refreshKopiaVersions(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.refreshKopiaVersions(body, readRequestContext(headers));
  }

  @Get('versions/:fileId')
  versions(
    @Param('fileId') fileId: string,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.versions(fileId, readRequestContext(headers));
  }

  @Post('versions/:versionId/download-requests')
  createVersionDownloadRequest(
    @Param('versionId') versionId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.createVersionDownloadRequest(
      versionId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('versions/:versionId/download-copy')
  downloadVersionCopy(
    @Param('versionId') versionId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.downloadVersionCopy(
      versionId,
      body,
      readRequestContext(headers),
    );
  }

  @Post('versions/:versionId/restore-prepare')
  prepareVersionRestore(
    @Param('versionId') versionId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.prepareVersionRestore(
      versionId,
      body,
      readRequestContext(headers),
    );
  }

  @Get('conflicts')
  conflicts(@Headers() headers: Record<string, unknown>) {
    return this.filesService.conflicts(readRequestContext(headers));
  }

  @Post('conflicts')
  createConflict(
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.createConflict(body, readRequestContext(headers));
  }

  @Post('conflicts/:conflictId/resolve')
  resolveConflict(
    @Param('conflictId') conflictId: string,
    @Body() body: Record<string, unknown>,
    @Headers() headers: Record<string, unknown>,
  ) {
    return this.filesService.resolveConflict(
      conflictId,
      body,
      readRequestContext(headers),
    );
  }
}
