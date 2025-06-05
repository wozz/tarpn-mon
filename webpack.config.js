const path = require('path');
const { VueLoaderPlugin } = require('vue-loader');

module.exports = {
  entry: './static/js/src/main.js',
  output: {
    path: path.resolve(__dirname, 'static/js/dist'),
    filename: 'main.js',
    publicPath: '/static/js/dist/'
  },
  module: {
    rules: [
      {
        test: /\.vue$/,
        loader: 'vue-loader'
      },
      {
        test: /\.js$/,
        exclude: /node_modules/,
        use: {
          loader: 'babel-loader',
          options: {
            presets: ['@babel/preset-env']
          }
        }
      },
      {
        test: /\.css$/,
        use: [
          'vue-style-loader',
          'css-loader'
        ]
      }
    ]
  },
  plugins: [
    new VueLoaderPlugin()
  ],
  resolve: {
    alias: {
      'vue$': 'vue/dist/vue.esm-bundler.js' // Use the runtime + compiler build
    },
    extensions: ['*', '.js', '.vue', '.json']
  },
  devServer: {
    static: {
      directory: path.join(__dirname, 'static'),
    },
    compress: true,
    port: 9000,
    proxy: {
      '/ws': {
        target: 'http://localhost:8212',
        ws: true
      },
      '/version': 'http://localhost:8212',
      '/api': 'http://localhost:8212' // If you had other API endpoints
    }
  }
}; 