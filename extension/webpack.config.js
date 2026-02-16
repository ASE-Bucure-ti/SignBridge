const path = require("path");
const CopyPlugin = require("copy-webpack-plugin");

module.exports = (env, argv) => {
  const target = env.target || "chrome";
  const isProduction = argv.mode === "production";

  return {
    mode: isProduction ? "production" : "development",
    devtool: isProduction ? false : "inline-source-map",

    entry: {
      "background/service-worker": "./src/background/service-worker.ts",
      "content/content-script": "./src/content/content-script.ts",
      "options/options": "./src/options/options.ts",
    },

    output: {
      path: path.resolve(__dirname, "dist", target),
      filename: "[name].js",
      clean: true,
    },

    resolve: {
      extensions: [".ts", ".js"],
    },

    module: {
      rules: [
        {
          test: /\.ts$/,
          use: "ts-loader",
          exclude: /node_modules/,
        },
      ],
    },

    plugins: [
      new CopyPlugin({
        patterns: [
          {
            from:
              target === "firefox" ? "manifest.firefox.json" : "manifest.json",
            to: "manifest.json",
          },
          { from: "src/options/options.html", to: "options/options.html" },
          { from: "src/options/options.css", to: "options/options.css" },
          { from: "static/icons", to: "icons", noErrorOnMissing: true },
        ],
      }),
    ],

    optimization: {
      minimize: isProduction,
    },
  };
};
