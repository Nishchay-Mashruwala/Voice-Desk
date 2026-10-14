import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import Overlay from "./views/Overlay";
import "./styles.css";

const isOverlay = window.location.hash === "#overlay";
if (isOverlay) document.documentElement.classList.add("overlay-root");

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>{isOverlay ? <Overlay /> : <App />}</React.StrictMode>,
);
