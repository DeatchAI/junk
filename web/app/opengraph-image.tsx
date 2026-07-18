import { ImageResponse } from "next/og";

export const alt = "Detach — AI agents for your entire Mac";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

export default function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          position: "relative",
          display: "flex",
          width: "100%",
          height: "100%",
          overflow: "hidden",
          background: "#f4f1eb",
          color: "#11100f",
          fontFamily: "Arial, sans-serif",
        }}
      >
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            background:
              "radial-gradient(circle at 82% 28%, rgba(255,121,0,0.36), transparent 38%)",
          }}
        />

        <div
          style={{
            position: "absolute",
            top: 0,
            left: 448,
            display: "flex",
            width: 304,
            height: 82,
            alignItems: "center",
            justifyContent: "center",
            gap: 14,
            borderRadius: "0 0 30px 30px",
            background: "#050505",
            color: "white",
            fontSize: 29,
            fontWeight: 700,
          }}
        >
          <div
            style={{
              display: "flex",
              width: 35,
              height: 29,
              gap: 4,
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <span
              style={{
                display: "flex",
                width: 14,
                height: 25,
                borderRadius: 5,
                background: "white",
                transform: "rotate(-8deg)",
              }}
            />
            <span
              style={{
                display: "flex",
                width: 14,
                height: 25,
                borderRadius: 5,
                background: "white",
                transform: "rotate(8deg)",
              }}
            />
          </div>
          Detach
        </div>

        <div
          style={{
            position: "relative",
            display: "flex",
            width: "100%",
            padding: "132px 78px 64px",
            flexDirection: "column",
            justifyContent: "space-between",
          }}
        >
          <div style={{ display: "flex", flexDirection: "column" }}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 11,
                fontSize: 20,
                fontWeight: 600,
                letterSpacing: "0.03em",
              }}
            >
              <span style={{ color: "#ff7900" }}>●</span>
              Ergonomic AI agents
            </div>
            <div
              style={{
                display: "flex",
                maxWidth: 840,
                marginTop: 30,
                fontSize: 82,
                fontWeight: 500,
                letterSpacing: "-0.055em",
                lineHeight: 0.93,
              }}
            >
              Your agents. Your whole Mac.
            </div>
          </div>

          <div
            style={{
              display: "flex",
              alignItems: "flex-end",
              justifyContent: "space-between",
            }}
          >
            <div
              style={{
                display: "flex",
                maxWidth: 620,
                color: "rgba(17,16,15,0.64)",
                fontSize: 25,
                lineHeight: 1.25,
              }}
            >
              Browser and macOS automation, detached coding, secure sign-in,
              integrations, workflows, and quick actions.
            </div>
            <div
              style={{
                display: "flex",
                padding: "16px 23px",
                borderRadius: 999,
                background: "#11100f",
                color: "white",
                fontSize: 21,
                fontWeight: 650,
              }}
            >
              Download for macOS ↗
            </div>
          </div>
        </div>
      </div>
    ),
    size,
  );
}
