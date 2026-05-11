# Build stage - Install dependencies
FROM php:8.3-fpm as builder

WORKDIR /app

# Install system dependencies and PHP extensions
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    curl \
    nodejs \
    npm \
    && docker-php-ext-install pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Allow Composer to run as root (required in Docker)
ENV COMPOSER_ALLOW_SUPERUSER=1

# Copy composer files
COPY composer.json composer.lock ./

# Install PHP dependencies WITHOUT running post-install scripts yet
RUN composer install --no-interaction --no-scripts --optimize-autoloader

# Copy application code
COPY . .

# Create .env file if it doesn't exist (for production builds)
RUN if [ ! -f /app/.env ]; then echo "APP_ENV=${APP_ENV:-prod}\nAPP_DEBUG=${APP_DEBUG:-false}\nAPP_SECRET=${APP_SECRET:-ChangeMe}\n" > /app/.env; fi

# Now run post-install scripts after app code is available
RUN composer install --no-interaction --optimize-autoloader --no-ansi || true
RUN php bin/console importmap:install --no-interaction

# Warm up cache for production
RUN php bin/console cache:warmup --env=prod --no-debug || true

# Production stage - Runtime with Nginx + PHP-FPM
FROM php:8.3-fpm as runtime

WORKDIR /app

# Install runtime dependencies + Nginx
RUN apt-get update && apt-get install -y \
    nginx \
    curl \
    && docker-php-ext-install pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

# Copy from builder stage
COPY --from=builder /app /app

# Create var directory if it doesn't exist and set proper permissions
RUN mkdir -p /app/var && \
    chown -R www-data:www-data /app && \
    chmod -R 755 /app && \
    chmod -R 775 /app/var

# Replace main Nginx config to avoid default site includes
COPY nginx-main.conf /etc/nginx/nginx.conf

# Remove all default Nginx configs and copy custom server block
RUN rm -rf /etc/nginx/conf.d/* /etc/nginx/sites-enabled /etc/nginx/sites-available
COPY nginx.conf /etc/nginx/conf.d/symfony.conf

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80

# Start both services
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]