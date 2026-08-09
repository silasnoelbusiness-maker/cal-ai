"use client";

import { useState } from "react";
import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";

export interface Faq {
  question: string;
  answer: string;
}

export function FaqEditor({ initialFaqs }: { initialFaqs: Faq[] }) {
  const [faqs, setFaqs] = useState<Faq[]>(initialFaqs.length > 0 ? initialFaqs : [{ question: "", answer: "" }]);

  return (
    <div className="space-y-3">
      <Label>Frequently asked questions</Label>
      <p className="text-xs text-muted">
        The AI answers from this list only — it never invents an answer to a question you haven&apos;t covered.
      </p>
      {faqs.map((faq, i) => (
        <div key={i} className="space-y-2 rounded-md border border-border p-3">
          <div className="flex items-center gap-2">
            <Input
              name="faq_question"
              placeholder="Question"
              value={faq.question}
              onChange={(e) => {
                const next = [...faqs];
                next[i] = { ...next[i], question: e.target.value };
                setFaqs(next);
              }}
            />
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="shrink-0 text-muted hover:text-danger"
              onClick={() => setFaqs(faqs.filter((_, idx) => idx !== i))}
              aria-label="Remove question"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          </div>
          <Textarea
            name="faq_answer"
            placeholder="Answer"
            rows={2}
            value={faq.answer}
            onChange={(e) => {
              const next = [...faqs];
              next[i] = { ...next[i], answer: e.target.value };
              setFaqs(next);
            }}
          />
        </div>
      ))}
      <Button type="button" variant="outline" size="sm" onClick={() => setFaqs([...faqs, { question: "", answer: "" }])}>
        <Plus className="h-4 w-4" />
        Add question
      </Button>
    </div>
  );
}
