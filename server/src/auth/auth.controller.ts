import { Body, Controller, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { LoginDto, RefreshDto } from './auth.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  login(@Body() body: LoginDto) {
    return this.authService.login(body);
  }

  @Post('refresh')
  refresh(@Body() body: RefreshDto) {
    return this.authService.refresh(body);
  }

  @Post('logout')
  logout() {
    return this.authService.logout();
  }
}
