"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Send, Sparkles } from "lucide-react";
import { ConversationBubble } from "@/components/conversations/conversation-bubble";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import type { Message, MessageSender } from "@prisma/client";

type PanelMessage = Pick<Message, "id" | "sender" | "content" | "aiGenerated" | "createdAt">;

export function ConversationPanel({
  conversationId,
  initialMessages,
}: {
  conversationId: string;
  initialMessages: PanelMessage[];
}) {
  const [messages, setMessages] = useState<PanelMessage[]>(initialMessages);
  const [draft, setDraft] = useState("");
  const [sending, startSending] = useTransition();
  const [suggesting, startSuggesting] = useTransition();
  const router = useRouter();
  const bottomRef = useRef<HTMLDivElement>(null);

  function scrollToBottom() {
    requestAnimationFrame(() => bottomRef.current?.scrollIntoView({ behavior: "smooth" }));
  }

  function send() {
    const content = draft.trim();
    if (!content) return;
    startSending(async () => {
      try {
        const res = await fetch(`/api/conversations/${conversationId}/messages`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content }),
        });
        const data = await res.json();
        if (!res.ok) {
          toast.error(data.error || "Couldn't send message.");
          return;
        }
        setMessages((prev) => [...prev, data.message]);
        setDraft("");
        scrollToBottom();
        router.refresh();
      } catch {
        toast.error("Couldn't send message. Check your connection.");
      }
    });
  }

  function suggestReply() {
    startSuggesting(async () => {
      try {
        const res = await fetch("/api/ai/reply", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ conversationId }),
        });
        const data = await res.json();
        if (!res.ok) {
          toast.error(data.error || "AI is temporarily unavailable.");
          return;
        }
        setDraft(data.content);
      } catch {
        toast.error("AI is temporarily unavailable. You can still reply manually.");
      }
    });
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <div className="flex-1 space-y-4 overflow-y-auto scrollbar-thin p-4">
        {messages.length === 0 ? (
          <p className="py-10 text-center text-sm text-muted">No messages yet.</p>
        ) : (
          messages.map((m) => (
            <ConversationBubble
              key={m.id}
              sender={m.sender as MessageSender}
              content={m.content}
              aiGenerated={m.aiGenerated}
              createdAt={m.createdAt}
            />
          ))
        )}
        <div ref={bottomRef} />
      </div>

      <div className="border-t border-border p-3">
        <Textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Write a message…"
          rows={3}
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
              e.preventDefault();
              send();
            }
          }}
        />
        <div className="mt-2 flex items-center justify-between gap-2">
          <Button
            type="button"
            variant="outline"
            size="sm"
            loading={suggesting}
            onClick={suggestReply}
          >
            <Sparkles className="h-3.5 w-3.5" />
            Suggest AI Reply
          </Button>
          <Button type="button" size="sm" loading={sending} disabled={!draft.trim()} onClick={send}>
            <Send className="h-3.5 w-3.5" />
            Send
          </Button>
        </div>
      </div>
    </div>
  );
}
