import { createFileRoute } from "@tanstack/react-router";
import { Workbench } from "@/components/rope/workbench";

export const Route = createFileRoute("/")({ component: Home });

function Home() {
  return <Workbench />;
}
