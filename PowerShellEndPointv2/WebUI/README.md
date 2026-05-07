# EMS Web UI - React Application

## Installation

### Prerequisites
- Node.js 16+ and npm
- PowerShell 5.1+

### Setup

```powershell
cd C:\Users\ZORO\PowerShellEndPointv2\WebUI

# Install dependencies
npm install

# Start development server
npm start
```

The application will open at `http://localhost:3000`

## Production Build

```powershell
# Build for production
npm run build

# Output will be in ./build directory
```

## IIS Deployment

See `../Deployment/IIS_Setup.md` for complete deployment instructions.

## Configuration

API endpoint is configured in `src/services/api.js`:
- Default: `http://localhost:5000/api`
- Override with environment variable: `REACT_APP_API_URL`

## Features

- **Authentication**: AD-based login with JWT tokens
- **Dashboard**: Real-time statistics and health monitoring
- **Scan Endpoints**: Single endpoint scanning with diagnostics
- **Results History**: Browse and filter historical scans
- **Responsive Design**: Works on desktop, tablet, and mobile

## Tech Stack

- React 18
- React Router 6  
- Axios for HTTP requests
- Modern CSS with CSS variables
