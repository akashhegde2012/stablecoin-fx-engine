import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Badge, badgeVariants } from "./badge";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "./card";
import { Input } from "./input";
import { Separator } from "./separator";
import { Skeleton } from "./skeleton";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "./tabs";

describe("ui primitives", () => {
  it("renders badge variants", () => {
    render(<Badge variant="destructive">Risk</Badge>);

    expect(screen.getByText("Risk")).toHaveClass("text-red-400");
    expect(badgeVariants({ variant: "outline", className: "extra" })).toContain("extra");
  });

  it("renders card composition slots", () => {
    render(
      <Card>
        <CardHeader>
          <CardTitle>Pool</CardTitle>
          <CardDescription>Stablecoin liquidity</CardDescription>
        </CardHeader>
        <CardContent>Content</CardContent>
        <CardFooter>Footer</CardFooter>
      </Card>,
    );

    expect(screen.getByText("Pool")).toBeInTheDocument();
    expect(screen.getByText("Stablecoin liquidity")).toBeInTheDocument();
    expect(screen.getByText("Content")).toBeInTheDocument();
    expect(screen.getByText("Footer")).toBeInTheDocument();
  });

  it("forwards input attributes and refs", () => {
    render(<Input aria-label="amount" placeholder="0.00" disabled className="custom-input" />);

    const input = screen.getByLabelText("amount");
    expect(input).toBeDisabled();
    expect(input).toHaveAttribute("placeholder", "0.00");
    expect(input).toHaveClass("custom-input");
  });

  it("renders skeleton and separators", () => {
    const { container } = render(
      <>
        <Skeleton data-testid="loading" className="h-4" />
        <Separator orientation="vertical" data-testid="separator" />
      </>,
    );

    expect(screen.getByTestId("loading")).toHaveClass("animate-pulse", "h-4");
    expect(screen.getByTestId("separator")).toHaveAttribute("data-orientation", "vertical");
    expect(container.querySelector(".h-full")).toBeInTheDocument();
  });

  it("renders tab triggers and active content", () => {
    render(
      <Tabs defaultValue="swap">
        <TabsList>
          <TabsTrigger value="swap">Swap</TabsTrigger>
          <TabsTrigger value="pools">Pools</TabsTrigger>
        </TabsList>
        <TabsContent value="swap">Swap panel</TabsContent>
        <TabsContent value="pools">Pools panel</TabsContent>
      </Tabs>,
    );

    expect(screen.getByRole("tab", { name: "Swap" })).toHaveAttribute("data-state", "active");
    expect(screen.getByText("Swap panel")).toBeInTheDocument();
  });
});
