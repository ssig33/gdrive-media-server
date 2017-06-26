FROM ssig33/ruby-imagemagick-groonga
RUN mkdir /app
WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle -j9
COPY . .
EXPOSE 5000
ENV PORT=5000
CMD foreman start

