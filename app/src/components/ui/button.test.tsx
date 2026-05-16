import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Button, buttonVariants } from "./button";

describe("Button", () => {
  it("renders button variants and forwards attributes", () => {
    render(
      <Button variant="secondary" size="sm" disabled>
        Save
      </Button>,
    );

    const button = screen.getByRole("button", { name: "Save" });
    expect(button).toBeDisabled();
    expect(button.className).toContain("h-9");
    expect(button.className).toContain("bg-kaia-surface");
  });

  it("exposes composable variant class generation", () => {
    expect(buttonVariants({ size: "icon", variant: "ghost", className: "extra" })).toContain("extra");
  });
});
