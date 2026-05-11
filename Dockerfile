# ============================================================
# Render.com Deployment Dockerfile
# OSGU Library Website — Next.js 16 + Bun + SQLite
# ============================================================

# ---------- Stage 1: Install dependencies ----------
FROM oven/bun:1.2 AS deps
WORKDIR /app

# Copy package files first (layer caching)
COPY package.json bun.lock ./

# Install ALL dependencies (including devDependencies needed for build)
RUN bun install --frozen-lockfile

# ---------- Stage 2: Build ----------
FROM oven/bun:1.2 AS builder
WORKDIR /app

# Copy everything from deps
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Generate Prisma client
RUN bunx prisma generate

# Build Next.js (standalone output)
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
RUN bun run build

# ---------- Stage 3: Production (minimal image) ----------
FROM oven/bun:1.2-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=10000
ENV DATABASE_URL="file:/data/library.db"

# Create non-root user for security
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

# Create persistent data directory for SQLite
RUN mkdir -p /data && chown nextjs:nodejs /data

# Copy standalone output
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

# Copy Prisma schema and seed script for runtime DB initialization
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma

# Copy the startup script (from ROOT — no subfolder)
COPY render-start.sh /app/render-start.sh
RUN chmod +x /app/render-start.sh

# Switch to non-root user
USER nextjs

# Expose the port Render expects
EXPOSE 10000

# Start the app
CMD ["/app/render-start.sh"]
