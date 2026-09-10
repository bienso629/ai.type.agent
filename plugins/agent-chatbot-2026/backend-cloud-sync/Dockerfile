FROM php:8.2-apache

# Cài đặt extension pdo_mysql
RUN docker-php-ext-install pdo pdo_mysql

# Kích hoạt mod_rewrite và mod_headers
RUN a2enmod rewrite headers

# Cấu hình Apache AllowOverride All
RUN sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# Copy toàn bộ mã nguồn PHP vào document root
WORKDIR /var/www/html
COPY . /var/www/html/

# Phân quyền thư mục
RUN chown -R www-data:www-data /var/www/html

EXPOSE 80
CMD ["apache2-foreground"]
