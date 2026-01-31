# Stride Backend API

Backend API service for the Stride running app, built with Node.js/Express and connected to Neon PostgreSQL.

## Setup

### 1. Prerequisites
- Node.js 18+
- A Neon database (get one at [neon.tech](https://neon.tech))
- Apple Developer account (for Sign in with Apple)

### 2. Install Dependencies
```bash
cd backend
npm install
```

### 3. Environment Variables
Create a `.env` file:
```env
# Neon Database
DATABASE_URL=postgresql://user:password@ep-xxx.region.neon.tech/database?sslmode=require

# Server
PORT=3000

# Apple Sign-In
APPLE_CLIENT_ID=com.yourcompany.stride  # Your app bundle ID
```

### 4. Database Setup
Run the SQL schema in your Neon console:
```bash
# The schema file is in the project root
cat ../neon_schema.sql
```

### 5. Run Locally
```bash
npm run dev
```

## Deploy to Railway

### 1. Create Railway Project
1. Go to [railway.app](https://railway.app)
2. Create new project from GitHub repo
3. Select this repository

### 2. Add Environment Variables
In Railway dashboard, add:
- `DATABASE_URL` - Your Neon connection string
- `APPLE_CLIENT_ID` - Your app bundle ID
- `PORT` - Railway sets this automatically

### 3. Deploy
Railway will auto-deploy on push to main branch.

## API Endpoints

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/apple` | Sign in with Apple |
| GET | `/auth/me` | Get current user |
| DELETE | `/auth/account` | Delete account |

### Workouts
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/workouts` | List all workouts |
| GET | `/workouts/:id` | Get workout details |
| POST | `/workouts` | Create workout |
| PUT | `/workouts/:id` | Update workout |
| DELETE | `/workouts/:id` | Delete workout |
| POST | `/workouts/:id/feedback` | Save feedback |

### Goals
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/goals` | List all goals |
| GET | `/goals/active` | Get active goal |
| POST | `/goals` | Create goal |
| PUT | `/goals/:id` | Update goal |
| DELETE | `/goals/:id` | Delete goal |
| POST | `/goals/:id/activate` | Set as active |

### Training Plans
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/plans/current` | Get current plan |
| POST | `/plans` | Save training plan |
| DELETE | `/plans/current` | Delete plan |
| PUT | `/plans/workouts/:id` | Update planned workout |
| GET | `/plans/assessments` | Get baseline assessments |
| POST | `/plans/assessments` | Save assessment |

### Profile
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/profile` | Get user profile |
| PUT | `/profile` | Update profile |
| GET | `/profile/preferences` | Get training preferences |
| PUT | `/profile/preferences` | Update preferences |

## Authentication

All endpoints except `/auth/*` and `/health` require authentication.

Include the Apple identity token in the Authorization header:
```
Authorization: Bearer <apple_identity_token>
```

The backend verifies the token against Apple's JWKS endpoint.
