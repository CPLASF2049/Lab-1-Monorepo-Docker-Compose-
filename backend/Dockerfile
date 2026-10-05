# Pinned to the Node.js 22 (LTS) line on Alpine; never `latest`.
FROM node:22-alpine

ENV NODE_ENV=production

WORKDIR /app

# Install only production dependencies from the committed lockfile, in a layer
# that is cached as long as package.json / package-lock.json do not change.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY server.js ./

# Run as the unprivileged user that the official node image already provides.
USER node

EXPOSE 3000

CMD ["node", "server.js"]
