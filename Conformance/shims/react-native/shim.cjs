// Minimal React Native stand-in for Node. Each primitive renders a DOM
// element named after the React Native component so a test can walk it.
const React = require("react");

function primitive(name) {
  const Component = ({ children, style, onPress, onLongPress, ...rest }) =>
    React.createElement(`rn-${name.toLowerCase()}`, { "data-rn": name }, children);
  Component.displayName = name;
  return Component;
}

const names = [
  "View", "Text", "Image", "ScrollView", "SafeAreaView", "Pressable",
  "TextInput", "Switch", "ActivityIndicator", "Modal",
];
const exportsObject = {};
for (const name of names) exportsObject[name] = primitive(name);
exportsObject.StyleSheet = { create: (styles) => styles, flatten: (s) => s };
exportsObject.Alert = { alert: () => {} };
exportsObject.Share = { share: async () => ({}) };
exportsObject.Linking = { canOpenURL: async () => true, openURL: async () => {} };
exportsObject.Platform = { OS: "ios", select: (o) => o.ios ?? o.default };
module.exports = exportsObject;
