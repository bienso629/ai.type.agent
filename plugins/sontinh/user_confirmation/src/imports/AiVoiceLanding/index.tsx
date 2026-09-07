import React, { useState, useEffect, useRef } from "react";
import { DotLottieReact } from "@lottiefiles/dotlottie-react";
import { Send, Mic, MicOff, Paperclip, X, Sparkles, Loader2, Maximize2 } from "lucide-react";
import imgAiVoiceLanding from "./bc29ab2cc877458bc63cbc1e6395177a1593c2ae.png";
import imgEllipse from "./cd0beadc01a5a41aa33a5bbd1ffcf605a4875d97.png";
import imgEllipse1 from "./6c2797ee1a2a59c9af7a133b18ffdc80aa467bfa.png";
import imgEllipse2 from "./ad28066826ae6990d66136b65a1999a132a5e053.png";
import imgEllipse3 from "./3a71ddf31bbd22e0149d7752cd14cf5f03aebd45.png";
import imgBrainFocal from "./8298ef825e454343ca61a878468ac7d19e5eaefd.png";
import aiAssistantLottie from "./ai_assistant.lottie";
import aiRoboData from "./ai_robo.json";
import aiRoboV2Data from "./ai_robo_v2.json";

const CATEGORY_PRESETS: Record<string, { label: string; prompt: string }> = {
  vietbai: {
    label: "Viết bài",
    prompt: "Viết một bài đăng Facebook chuyên nghiệp giới thiệu trợ lý Mì Tôm AI đa năng.",
  },
  lamvlog: {
    label: "Làm Vlog",
    prompt: "Bắt buộc tạo video: Giới thiệu tính năng tự động hóa hệ thống của Mì Tôm AI",
  },
  quangcao: {
    label: "Quảng cáo",
    prompt: "Soạn 3 mẫu kịch bản quảng cáo ngắn thu hút cho dịch vụ trợ lý AI cá nhân.",
  },
  thietke: {
    label: "Thiết kế",
    prompt: "Bắt buộc tạo hình ảnh: Robot AI tương lai trong thành phố Cyberpunk rực rỡ kích thước 4k",
  },
  mangxahoi: {
    label: "Mạng xã hội",
    prompt: "Lên kế hoạch nội dung mạng xã hội 7 ngày cho thương hiệu công nghệ mới.",
  },
  timkiem: {
    label: "Tìm kiếm",
    prompt: "Tìm kiếm thông tin bài hát hot nhất trên YouTube và mở phát bài hát đó.",
  },
  marketing: {
    label: "Marketing",
    prompt: "Chiến lược tăng trưởng Marketing cho sản phẩm phần mềm tự động hóa.",
  },
  giadinh: {
    label: "Gia đình",
    prompt: "Gợi ý danh sách việc cần làm và thực đơn bữa tối ấm cúng cho gia đình.",
  },
};

function Frame({ isStreaming }: { isStreaming?: boolean }) {
  return (
    <div className="absolute bottom-4 left-1/2 -translate-x-1/2 flex gap-[8px] items-center justify-center bg-black/40 backdrop-blur-md px-3 py-1 rounded-full pointer-events-none z-20" data-name="Frame">
      <div className="relative shrink-0 size-[8px]" data-name="Ellipse">
        <svg className="absolute block inset-0 size-full" fill="none" height="8" preserveAspectRatio="none" viewBox="0 0 8 8" width="8">
          <circle cx="4" cy="4" fill={isStreaming ? "#F59E0B" : "#10B981"} id="Ellipse" r="4" className={isStreaming ? "animate-ping" : ""} />
        </svg>
      </div>
      <p className="[word-break:break-word] font-['Montserrat:SemiBold',sans-serif] font-semibold leading-[normal] relative shrink-0 text-[#10b981] text-[11px] whitespace-nowrap">
        {isStreaming ? "BUSY" : "LIVE"}
      </p>
    </div>
  );
}

function BrainFocal({ onClick, isStreaming }: { onClick?: () => void; isStreaming?: boolean }) {
  const [currentAction, setCurrentAction] = useState<"idle" | "yes">("idle");
  const [playKey, setPlayKey] = useState(0);

  const handleRobotClick = () => {
    setCurrentAction("yes");
    setPlayKey((prev) => prev + 1);
    if (onClick) onClick();
  };

  return (
    <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 z-20 pointer-events-auto flex items-center justify-center">
      <div
        onClick={handleRobotClick}
        className="relative overflow-hidden rounded-full size-[380px] md:size-[420px] cursor-pointer group hover:scale-105 transition-transform duration-300 flex items-center justify-center"
        data-name="brain-focal"
        title="Bấm để kích hoạt robot AI (Gật đầu) & mở bảng điều hành"
      >
        {/* User Provided AI Robot V2 Lottie Animation */}
        <div className="w-full h-full flex items-center justify-center p-0 m-0">
          <DotLottieReact
            key={`${currentAction}-${playKey}`}
            data={aiRoboV2Data}
            segment={currentAction === "yes" ? [31, 105] : [0, 29]}
            autoplay={true}
            loop={currentAction === "idle"}
            dotLottieRefCallback={(dotLottie) => {
              if (dotLottie && currentAction === "yes") {
                const onComplete = () => {
                  setCurrentAction("idle");
                  setPlayKey((prev) => prev + 1);
                };
                dotLottie.addEventListener("complete", onComplete);
              }
            }}
            className="w-full h-full object-contain pointer-events-none"
          />
        </div>

        <Frame isStreaming={isStreaming} />
      </div>
    </div>
  );
}

function Frame1() {
  return (
    <div className="relative shrink-0 size-[24px]" data-name="Frame">
      <svg className="absolute block inset-0 size-full" fill="none" height="24" preserveAspectRatio="none" viewBox="0 0 24 24" width="24">
        <g id="Frame">
          <rect fill="var(--fill-0, #06B6D4)" fillOpacity="0.0823529" height="23" rx="11.5" width="23" x="0.5" y="0.5" />
          <rect height="23" rx="11.5" stroke="var(--stroke-0, #06B6D4)" width="23" x="0.5" y="0.5" />
          <circle cx="12" cy="12" fill="var(--fill-0, #06B6D4)" id="Ellipse" r="5" />
        </g>
      </svg>
    </div>
  );
}

function Frame2() {
  return (
    <div className="[word-break:break-word] content-stretch flex flex-col gap-[2px] items-start leading-[normal] relative shrink-0 whitespace-nowrap" data-name="Frame">
      <p className="font-['Montserrat:SemiBold',sans-serif] font-semibold relative shrink-0 text-[#e2e8f0] text-[14px]">Viết bài</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[10px] text-[rgba(6,182,212,0.5)]">CONTENT</p>
    </div>
  );
}

function PlanetVietBai({ onClick }: { onClick?: () => void }) {
  return (
    <div onClick={onClick} className="absolute content-stretch flex gap-[10px] items-center left-[60.4%] top-[35.5%] cursor-pointer group hover:scale-110 transition-transform duration-200 z-10" data-name="planet-viet-bai">
      <Frame1 />
      <Frame2 />
    </div>
  );
}

function Frame3() {
  return (
    <div className="relative shrink-0 size-[22px]" data-name="Frame">
      <svg className="absolute block inset-0 size-full" fill="none" height="22" preserveAspectRatio="none" viewBox="0 0 22 22" width="22">
        <g id="Frame">
          <rect fill="var(--fill-0, #A855F7)" fillOpacity="0.0823529" height="21" rx="10.5" width="21" x="0.5" y="0.5" />
          <rect height="21" rx="10.5" stroke="var(--stroke-0, #A855F7)" width="21" x="0.5" y="0.5" />
          <circle cx="11" cy="11" fill="var(--fill-0, #A855F7)" id="Ellipse" r="4.5" />
        </g>
      </svg>
    </div>
  );
}

function Frame4() {
  return (
    <div className="[word-break:break-word] content-stretch flex flex-col gap-[2px] items-start leading-[normal] relative shrink-0 whitespace-nowrap" data-name="Frame">
      <p className="font-['Montserrat:SemiBold',sans-serif] font-semibold relative shrink-0 text-[#e2e8f0] text-[14px]">Làm Vlog</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[10px] text-[rgba(168,85,247,0.5)]">VIDEO</p>
    </div>
  );
}

function PlanetLamVlog({ onClick }: { onClick?: () => void }) {
  return (
    <div onClick={onClick} className="absolute content-stretch flex gap-[10px] items-center left-[30.5%] top-[61.1%] cursor-pointer group hover:scale-110 transition-transform duration-200 z-10" data-name="planet-lam-vlog">
      <Frame3 />
      <Frame4 />
    </div>
  );
}

function Frame5() {
  return (
    <div className="relative shrink-0 size-[26px]" data-name="Frame">
      <svg className="absolute block inset-0 size-full" fill="none" height="26" preserveAspectRatio="none" viewBox="0 0 26 26" width="26">
        <g id="Frame">
          <rect fill="var(--fill-0, #F59E0B)" fillOpacity="0.0823529" height="25" rx="12.5" width="25" x="0.5" y="0.5" />
          <rect height="25" rx="12.5" stroke="var(--stroke-0, #F59E0B)" width="25" x="0.5" y="0.5" />
          <circle cx="13" cy="13" fill="var(--fill-0, #F59E0B)" id="Ellipse" r="5.5" />
        </g>
      </svg>
    </div>
  );
}

function Frame6() {
  return (
    <div className="[word-break:break-word] content-stretch flex flex-col gap-[2px] items-start leading-[normal] relative shrink-0 whitespace-nowrap" data-name="Frame">
      <p className="font-['Montserrat:SemiBold',sans-serif] font-semibold relative shrink-0 text-[#e2e8f0] text-[14px]">Quảng cáo</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[10px] text-[rgba(245,158,11,0.5)]">ADS</p>
    </div>
  );
}

function PlanetQuangCao({ onClick }: { onClick?: () => void }) {
  return (
    <div onClick={onClick} className="absolute content-stretch flex gap-[10px] items-center left-[34%] top-[25.5%] cursor-pointer group hover:scale-110 transition-transform duration-200 z-10" data-name="planet-quang-cao">
      <Frame5 />
      <Frame6 />
    </div>
  );
}

function Frame7() {
  return (
    <div className="relative shrink-0 size-[28px]" data-name="Frame">
      <svg className="absolute block inset-0 size-full" fill="none" height="28" preserveAspectRatio="none" viewBox="0 0 28 28" width="28">
        <g id="Frame">
          <rect fill="var(--fill-0, #10B981)" fillOpacity="0.0823529" height="27" rx="13.5" width="27" x="0.5" y="0.5" />
          <rect height="27" rx="13.5" stroke="var(--stroke-0, #10B981)" width="27" x="0.5" y="0.5" />
          <circle cx="14" cy="14" fill="var(--fill-0, #10B981)" id="Ellipse" r="6" />
        </g>
      </svg>
    </div>
  );
}

function Frame8() {
  return (
    <div className="[word-break:break-word] content-stretch flex flex-col gap-[2px] items-start leading-[normal] relative shrink-0 whitespace-nowrap" data-name="Frame">
      <p className="font-['Montserrat:SemiBold',sans-serif] font-semibold relative shrink-0 text-[#e2e8f0] text-[14px]">Thiết kế</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[10px] text-[rgba(16,185,129,0.5)]">DESIGN</p>
    </div>
  );
}

function PlanetThietKe({ onClick }: { onClick?: () => void }) {
  return (
    <div onClick={onClick} className="absolute content-stretch flex gap-[10px] items-center left-[36.8%] top-[81.1%] cursor-pointer group hover:scale-110 transition-transform duration-200 z-10" data-name="planet-thiet-ke">
      <Frame7 />
      <Frame8 />
    </div>
  );
}

function Frame9() {
  return (
    <div className="relative shrink-0 size-[24px]" data-name="Frame">
      <svg className="absolute block inset-0 size-full" fill="none" height="24" preserveAspectRatio="none" viewBox="0 0 24 24" width="24">
        <g id="Frame">
          <rect fill="var(--fill-0, #06B6D4)" fillOpacity="0.0823529" height="23" rx="11.5" width="23" x="0.5" y="0.5" />
          <rect height="23" rx="11.5" stroke="var(--stroke-0, #06B6D4)" width="23" x="0.5" y="0.5" />
          <circle cx="12" cy="12" fill="var(--fill-0, #06B6D4)" id="Ellipse" r="5" />
        </g>
      </svg>
    </div>
  );
}

function Frame10() {
  return (
    <div className="[word-break:break-word] content-stretch flex flex-col gap-[2px] items-start leading-[normal] relative shrink-0 whitespace-nowrap" data-name="Frame">
      <p className="font-['Montserrat:SemiBold',sans-serif] font-semibold relative shrink-0 text-[#e2e8f0] text-[14px]">Mạng xã hội</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[10px] text-[rgba(6,182,212,0.5)]">SOCIAL</p>
    </div>
  );
}

function PlanetMangXaHoi({ onClick }: { onClick?: () => void }) {
  return (
    <div onClick={onClick} className="absolute content-stretch flex gap-[10px] items-center left-[70.1%] top-[54.4%] cursor-pointer group hover:scale-110 transition-transform duration-200 z-10" data-name="planet-mang-xa-hoi">
      <Frame9 />
      <Frame10 />
    </div>
  );
}

function Frame11() {
  return (
    <div className="relative shrink-0 size-[22px]" data-name="Frame">
      <svg className="absolute block inset-0 size-full" fill="none" height="22" preserveAspectRatio="none" viewBox="0 0 22 22" width="22">
        <g id="Frame">
          <rect fill="var(--fill-0, #F472B6)" fillOpacity="0.0823529" height="21" rx="10.5" width="21" x="0.5" y="0.5" />
          <rect height="21" rx="10.5" stroke="var(--stroke-0, #F472B6)" width="21" x="0.5" y="0.5" />
          <circle cx="11" cy="11" fill="var(--fill-0, #F472B6)" id="Ellipse" r="4.5" />
        </g>
      </svg>
    </div>
  );
}

function Frame12() {
  return (
    <div className="[word-break:break-word] content-stretch flex flex-col gap-[2px] items-start leading-[normal] relative shrink-0 whitespace-nowrap" data-name="Frame">
      <p className="font-['Montserrat:SemiBold',sans-serif] font-semibold relative shrink-0 text-[#e2e8f0] text-[14px]">Tìm kiếm</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[10px] text-[rgba(244,114,182,0.5)]">SEARCH</p>
    </div>
  );
}

function PlanetTimKiem({ onClick }: { onClick?: () => void }) {
  return (
    <div onClick={onClick} className="absolute content-stretch flex gap-[10px] items-center left-[15.3%] top-[53.3%] cursor-pointer group hover:scale-110 transition-transform duration-200 z-10" data-name="planet-tim-kiem">
      <Frame11 />
      <Frame12 />
    </div>
  );
}

function Frame13() {
  return (
    <div className="relative shrink-0 size-[30px]" data-name="Frame">
      <svg className="absolute block inset-0 size-full" fill="none" height="30" preserveAspectRatio="none" viewBox="0 0 30 30" width="30">
        <g id="Frame">
          <rect fill="var(--fill-0, #F59E0B)" fillOpacity="0.0941176" height="29" rx="14.5" width="29" x="0.5" y="0.5" />
          <rect height="29" rx="14.5" stroke="var(--stroke-0, #F59E0B)" width="29" x="0.5" y="0.5" />
          <circle cx="15" cy="15" fill="var(--fill-0, #F59E0B)" id="Ellipse" r="6.5" />
        </g>
      </svg>
    </div>
  );
}

function Frame14() {
  return (
    <div className="[word-break:break-word] content-stretch flex flex-col gap-[2px] items-start leading-[normal] relative shrink-0 whitespace-nowrap" data-name="Frame">
      <p className="font-['Montserrat:Bold',sans-serif] font-bold relative shrink-0 text-[#f1f5f9] text-[15px]">Marketing</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[10px] text-[rgba(245,158,11,0.5)]">GROWTH</p>
    </div>
  );
}

function PlanetMarketing({ onClick }: { onClick?: () => void }) {
  return (
    <div onClick={onClick} className="absolute content-stretch flex gap-[10px] items-center left-[75%] top-[36.6%] cursor-pointer group hover:scale-110 transition-transform duration-200 z-10" data-name="planet-marketing">
      <Frame13 />
      <Frame14 />
    </div>
  );
}

function Frame15() {
  return (
    <div className="relative shrink-0 size-[30px]" data-name="Frame">
      <svg className="absolute block inset-0 size-full" fill="none" height="30" preserveAspectRatio="none" viewBox="0 0 30 30" width="30">
        <g id="Frame">
          <rect fill="var(--fill-0, #EC4899)" fillOpacity="0.0941176" height="29" rx="14.5" width="29" x="0.5" y="0.5" />
          <rect height="29" rx="14.5" stroke="var(--stroke-0, #EC4899)" width="29" x="0.5" y="0.5" />
          <circle cx="15" cy="15" fill="var(--fill-0, #EC4899)" id="Ellipse" r="6.5" />
        </g>
      </svg>
    </div>
  );
}

function Frame16() {
  return (
    <div className="[word-break:break-word] content-stretch flex flex-col gap-[2px] items-start leading-[normal] relative shrink-0 whitespace-nowrap" data-name="Frame">
      <p className="font-['Montserrat:Bold',sans-serif] font-bold relative shrink-0 text-[#f1f5f9] text-[15px]">Gia đình</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[10px] text-[rgba(236,72,153,0.5)]">FAMILY</p>
    </div>
  );
}

function PlanetGiaDinh({ onClick }: { onClick?: () => void }) {
  return (
    <div onClick={onClick} className="absolute content-stretch flex gap-[10px] items-center left-[4.2%] top-[36.6%] cursor-pointer group hover:scale-110 transition-transform duration-200 z-10" data-name="planet-gia-dinh">
      <Frame15 />
      <Frame16 />
    </div>
  );
}

function Frame17({ isStreaming }: { isStreaming?: boolean }) {
  return (
    <div className="absolute content-stretch flex gap-[4px] h-[60px] items-center justify-center left-1/2 -translate-x-1/2 bottom-[14%] w-[320px] pointer-events-none" data-name="Frame">
      <div className={`bg-[rgba(6,182,212,0.16)] h-[8px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.25)] h-[14px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.22)] h-[10px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.31)] h-[20px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.28)] h-[16px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.38)] h-[28px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[36px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[44px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[52px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[42px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[56px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[48px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[58px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[50px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[40px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[54px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[46px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[#06b6d4] h-[38px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.44)] h-[32px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.35)] h-[24px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.28)] h-[18px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.22)] h-[14px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.16)] h-[10px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
      <div className={`bg-[rgba(6,182,212,0.13)] h-[8px] relative rounded-[2px] shrink-0 w-[3px] ${isStreaming ? "animate-pulse" : ""}`} data-name="Rectangle" />
    </div>
  );
}

function Spacer() {
  return <div className="flex-[1_0_0] h-[13px] min-w-px relative" data-name="spacer" />;
}

function Frame18({ statusText }: { statusText?: string }) {
  return (
    <div className="absolute content-stretch flex gap-[8px] items-center left-[40px] right-[40px] bottom-[20px] w-auto" data-name="Frame">
      <p className="[word-break:break-word] font-['Montserrat:Regular',sans-serif] font-normal leading-[normal] relative shrink-0 text-[#10b981] text-[11px] uppercase whitespace-nowrap">{statusText || "TRANSCRIBING"}</p>
      <p className="[word-break:break-word] font-['Montserrat:Regular',sans-serif] font-normal leading-[normal] relative shrink-0 text-[#475569] text-[11px] whitespace-nowrap">·</p>
      <p className="[word-break:break-word] font-['Montserrat:Regular',sans-serif] font-normal leading-[normal] relative shrink-0 text-[#475569] text-[11px] whitespace-nowrap">CONFIDENCE</p>
      <p className="[word-break:break-word] font-['Montserrat:Regular',sans-serif] font-normal leading-[normal] relative shrink-0 text-[#f59e0b] text-[11px] whitespace-nowrap">98.4%</p>
      <Spacer />
      <p className="[word-break:break-word] font-['Montserrat:Regular',sans-serif] font-normal leading-[normal] relative shrink-0 text-[#667380] text-[11px] uppercase whitespace-nowrap">Thiết kế bởi Yên AI</p>
    </div>
  );
}

function DateWeatherInfo({ dateStr }: { dateStr?: string }) {
  return (
    <div className="[word-break:break-word] absolute content-stretch flex gap-[20px] items-start leading-[normal] right-[40px] overflow-clip text-[13px] top-[20px] whitespace-nowrap" data-name="date-weather-info">
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[#b2bfcc]">{dateStr || "28 Tháng 7, 2026"}</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[#667380]">|</p>
      <p className="font-['Montserrat:SemiBold',sans-serif] font-semibold relative shrink-0 text-[#b2bfcc]">32°C</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[#808c99]">Hà Nội</p>
    </div>
  );
}

function News() {
  return (
    <div className="content-stretch flex flex-col gap-[4px] items-start overflow-clip relative shrink-0" data-name="news-1">
      <p className="font-['Montserrat:Medium',sans-serif] font-medium relative shrink-0 text-[#d9e0e5] text-[12px]">AI vượt mốc 1 tỷ người dùng toàn cầu</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[#667380] text-[9px]">2 giờ trước</p>
    </div>
  );
}

function News1() {
  return (
    <div className="content-stretch flex flex-col gap-[4px] items-start overflow-clip relative shrink-0" data-name="news-2">
      <p className="font-['Montserrat:Medium',sans-serif] font-medium relative shrink-0 text-[#d9e0e5] text-[12px]">Việt Nam ra mắt trợ lý ảo đa ngôn ngữ</p>
      <p className="font-['Montserrat:Regular',sans-serif] font-normal relative shrink-0 text-[#667380] text-[9px]">5 giờ trước</p>
    </div>
  );
}

function LatestNews() {
  return (
    <div className="[word-break:break-word] absolute content-stretch flex flex-col gap-[16px] items-start leading-[normal] left-[40px] overflow-clip top-[20px] whitespace-nowrap" data-name="latest-news">
      <p className="font-['Montserrat:Bold',sans-serif] font-bold relative shrink-0 text-[#05b5d4] text-[10px] tracking-[2px]">TIN MỚI</p>
      <News />
      <News1 />
    </div>
  );
}

interface MessageItem {
  id: string;
  sender: "user" | "agent";
  text: string;
  image?: string;
  video?: string;
  audio?: string;
  isError?: boolean;
}

export default function AiVoiceLanding() {
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [promptInput, setPromptInput] = useState("");
  const [selectedModel, setSelectedModel] = useState("gemini-2.5-flash");
  const [ttsVoice, setTtsVoice] = useState("vi-VN-HoaiMyNeural");
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  
  const [messages, setMessages] = useState<MessageItem[]>([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [statusText, setStatusText] = useState<string>("SẴN SÀNG");
  const [isListening, setIsListening] = useState(false);
  const [previewMedia, setPreviewMedia] = useState<{ type: "image" | "video"; src: string } | null>(null);

  const [dateStr, setDateStr] = useState("");
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const messagesEndRef = useRef<HTMLDivElement | null>(null);
  const recognitionRef = useRef<any>(null);

  useEffect(() => {
    const updateDateTime = () => {
      const now = new Date();
      const options: Intl.DateTimeFormatOptions = { day: "numeric", month: "long", year: "numeric" };
      setDateStr(now.toLocaleDateString("vi-VN", options));
    };
    updateDateTime();
    const interval = setInterval(updateDateTime, 60000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, [messages, isStreaming]);

  const toggleSpeechRecognition = () => {
    if (isListening) {
      if (recognitionRef.current) recognitionRef.current.stop();
      setIsListening(false);
      return;
    }

    const SpeechRecognition = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;
    if (!SpeechRecognition) {
      alert("Trình duyệt của bạn không hỗ trợ nhận diện giọng nói (Speech Recognition). Vui lòng nhập văn bản.");
      return;
    }

    const recognition = new SpeechRecognition();
    recognition.lang = "vi-VN";
    recognition.interimResults = true;
    recognition.continuous = false;

    recognition.onstart = () => {
      setIsListening(true);
    };

    recognition.onresult = (event: any) => {
      const transcript = Array.from(event.results)
        .map((result: any) => result[0].transcript)
        .join("");
      setPromptInput(transcript);
    };

    recognition.onerror = (err: any) => {
      console.error("Speech Recognition Error:", err);
      setIsListening(false);
    };

    recognition.onend = () => {
      setIsListening(false);
    };

    recognitionRef.current = recognition;
    recognition.start();
  };

  const handleOpenCategory = (key: string) => {
    const preset = CATEGORY_PRESETS[key];
    if (preset) {
      setPromptInput(preset.prompt);
    }
    setIsModalOpen(true);
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      setSelectedFiles(Array.from(e.target.files));
    }
  };

  const handleExecute = async () => {
    if (!promptInput.trim() && selectedFiles.length === 0) return;

    const currentPrompt = promptInput.trim();
    const userMsgId = Date.now().toString();
    
    setMessages((prev) => [
      ...prev,
      { id: userMsgId, sender: "user", text: currentPrompt }
    ]);

    setPromptInput("");
    setIsStreaming(true);
    setStatusText("ĐANG XỬ LÝ YÊU CẦU...");

    const agentMsgId = (Date.now() + 1).toString();
    setMessages((prev) => [
      ...prev,
      { id: agentMsgId, sender: "agent", text: "" }
    ]);

    try {
      const formData = new FormData();
      formData.append("prompt", currentPrompt);
      formData.append("system_instructions", "Bạn là trợ lý Mì Tôm AI thông minh, hỗ trợ người dùng tối đa.");
      formData.append("model", selectedModel);
      formData.append("tts_voice", ttsVoice);
      formData.append("conversation_id", "default_session");

      for (const file of selectedFiles) {
        formData.append("files", file);
      }
      setSelectedFiles([]);

      const response = await fetch("/api/chat", {
        method: "POST",
        headers: {
          "x-api-key": "type-vn-local-agent-2026",
        },
        body: formData,
      });

      if (!response.ok) {
        throw new Error(`Server báo lỗi HTTP: ${response.status}`);
      }

      const reader = response.body?.getReader();
      const decoder = new TextDecoder("utf-8");
      let buffer = "";

      if (reader) {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split("\n");
          buffer = lines.pop() || "";

          for (const line of lines) {
            if (line.startsWith("data: ")) {
              const jsonStr = line.replace("data: ", "").trim();
              if (!jsonStr) continue;

              try {
                const data = JSON.parse(jsonStr);

                if (data.error) {
                  setMessages((prev) =>
                    prev.map((msg) =>
                      msg.id === agentMsgId
                        ? { ...msg, text: msg.text + `\n⚠️ Lỗi: ${data.error}`, isError: true }
                        : msg
                    )
                  );
                }

                if (data.content) {
                  setMessages((prev) =>
                    prev.map((msg) =>
                      msg.id === agentMsgId
                        ? { ...msg, text: msg.text + data.content }
                        : msg
                    )
                  );
                }

                if (data.audio_base64) {
                  const audioSrc = `data:audio/mp3;base64,${data.audio_base64}`;
                  if (audioRef.current) {
                    audioRef.current.src = audioSrc;
                    audioRef.current.play().catch((err) => console.log("Audio play blocked:", err));
                  }
                }

                if (data.image_base64) {
                  setMessages((prev) =>
                    prev.map((msg) =>
                      msg.id === agentMsgId
                        ? { ...msg, image: `data:image/png;base64,${data.image_base64}` }
                        : msg
                    )
                  );
                }

                if (data.video_base64) {
                  setMessages((prev) =>
                    prev.map((msg) =>
                      msg.id === agentMsgId
                        ? { ...msg, video: `data:video/mp4;base64,${data.video_base64}` }
                        : msg
                    )
                  );
                }
              } catch (err) {
                console.error("Lỗi parse SSE:", err, line);
              }
            }
          }
        }
      }

      setStatusText("HOÀN THÀNH");
    } catch (err: any) {
      console.error("Lỗi thực thi:", err);
      setMessages((prev) =>
        prev.map((msg) =>
          msg.id === agentMsgId
            ? { ...msg, text: msg.text + `\n❌ Lỗi kết nối: ${err.message}`, isError: true }
            : msg
        )
      );
      setStatusText("LỖI KẾT NỐI");
    } finally {
      setIsStreaming(false);
    }
  };

  return (
    <div className="fixed inset-0 w-screen h-screen overflow-hidden bg-[#02040a] select-none" data-name="ai-voice-landing">
      <audio ref={audioRef} className="hidden" />

      {/* Background image & overlay */}
      <div aria-hidden className="absolute inset-0 pointer-events-none">
        <img alt="" className="absolute inset-0 w-full h-full object-cover opacity-80" src={imgAiVoiceLanding} />
        <div className="absolute bg-[rgba(2,4,10,0.35)] inset-0" />
      </div>

      {/* Background SVG Ellipses & Glow Filters */}
      <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 size-[600px]" data-name="Ellipse">
        <div className="absolute inset-[-30%]">
          <svg className="block size-full" fill="none" height="960" preserveAspectRatio="none" viewBox="0 0 960 960" width="960">
            <g filter="url(#filter0_f_1_49)" id="Ellipse" opacity="0.26775">
              <circle cx="480" cy="480" fill="var(--fill-0, #06B6D4)" fillOpacity="0.0313726" r="300" />
            </g>
            <defs>
              <filter colorInterpolationFilters="sRGB" filterUnits="userSpaceOnUse" height="960" id="filter0_f_1_49" width="960" x="0" y="0">
                <feFlood floodOpacity="0" result="BackgroundImageFix" />
                <feBlend in="SourceGraphic" in2="BackgroundImageFix" mode="normal" result="shape" />
                <feGaussianBlur result="effect1_foregroundBlur_1_49" stdDeviation="90" />
              </filter>
            </defs>
          </svg>
        </div>
      </div>
      <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 size-[500px]" data-name="Ellipse">
        <div className="absolute inset-[-32%]">
          <svg className="block size-full" fill="none" height="820" preserveAspectRatio="none" viewBox="0 0 820 820" width="820">
            <g filter="url(#filter0_f_1_47)" id="Ellipse" opacity="0.308875">
              <circle cx="410" cy="410" fill="var(--fill-0, #F59E0B)" fillOpacity="0.0156863" r="250" />
            </g>
            <defs>
              <filter colorInterpolationFilters="sRGB" filterUnits="userSpaceOnUse" height="820" id="filter0_f_1_47" width="820" x="0" y="0">
                <feFlood floodOpacity="0" result="BackgroundImageFix" />
                <feBlend in="SourceGraphic" in2="BackgroundImageFix" mode="normal" result="shape" />
                <feGaussianBlur result="effect1_foregroundBlur_1_47" stdDeviation="80" />
              </filter>
            </defs>
          </svg>
        </div>
      </div>
      <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 size-[650px]" data-name="Ellipse">
        <div className="absolute inset-[-30.77%]">
          <svg className="block size-full" fill="none" height="1050" preserveAspectRatio="none" viewBox="0 0 1050 1050" width="1050">
            <g filter="url(#filter0_f_1_61)" id="Ellipse" opacity="0.1855">
              <circle cx="525" cy="525" fill="var(--fill-0, #06B6D4)" fillOpacity="0.0235294" r="325" />
            </g>
            <defs>
              <filter colorInterpolationFilters="sRGB" filterUnits="userSpaceOnUse" height="1050" id="filter0_f_1_61" width="1050" x="0" y="0">
                <feFlood floodOpacity="0" result="BackgroundImageFix" />
                <feBlend in="SourceGraphic" in2="BackgroundImageFix" mode="normal" result="shape" />
                <feGaussianBlur result="effect1_foregroundBlur_1_61" stdDeviation="100" />
              </filter>
            </defs>
          </svg>
        </div>
      </div>



      {/* Main Brain Focal Component */}
      <BrainFocal onClick={() => setIsModalOpen(true)} isStreaming={isStreaming} />

      {/* Planet SVG Components */}
      <PlanetVietBai onClick={() => handleOpenCategory("vietbai")} />
      <PlanetLamVlog onClick={() => handleOpenCategory("lamvlog")} />
      <PlanetQuangCao onClick={() => handleOpenCategory("quangcao")} />
      <PlanetThietKe onClick={() => handleOpenCategory("thietke")} />
      <PlanetMangXaHoi onClick={() => handleOpenCategory("mangxahoi")} />
      <PlanetTimKiem onClick={() => handleOpenCategory("timkiem")} />
      <PlanetMarketing onClick={() => handleOpenCategory("marketing")} />
      <PlanetGiaDinh onClick={() => handleOpenCategory("giadinh")} />

      {/* Star/Dot SVG Elements */}
      <div className="absolute left-[22%] size-[3px] top-[20%]" data-name="Ellipse">
        <svg className="absolute block inset-0 size-full" fill="none" height="3" preserveAspectRatio="none" viewBox="0 0 3 3" width="3">
          <circle cx="1.5" cy="1.5" fill="var(--fill-0, #06B6D4)" id="Ellipse" opacity="0.35" r="1.5" />
        </svg>
      </div>
      <div className="absolute left-[73%] size-[2px] top-[28%]" data-name="Ellipse">
        <svg className="absolute block inset-0 size-full" fill="none" height="2" preserveAspectRatio="none" viewBox="0 0 2 2" width="2">
          <circle cx="1" cy="1" fill="var(--fill-0, #F59E0B)" id="Ellipse" opacity="0.35" r="1" />
        </svg>
      </div>
      <div className="absolute left-[18%] size-[3px] top-[44%]" data-name="Ellipse">
        <svg className="absolute block inset-0 size-full" fill="none" height="3" preserveAspectRatio="none" viewBox="0 0 3 3" width="3">
          <circle cx="1.5" cy="1.5" fill="var(--fill-0, #A855F7)" id="Ellipse" opacity="0.28" r="1.5" />
        </svg>
      </div>
      <div className="absolute left-[80%] size-[2px] top-[55%]" data-name="Ellipse">
        <svg className="absolute block inset-0 size-full" fill="none" height="2" preserveAspectRatio="none" viewBox="0 0 2 2" width="2">
          <circle cx="1" cy="1" fill="var(--fill-0, #06B6D4)" id="Ellipse" opacity="0.28" r="1" />
        </svg>
      </div>
      <div className="absolute left-[12%] size-[3px] top-[68%]" data-name="Ellipse">
        <svg className="absolute block inset-0 size-full" fill="none" height="3" preserveAspectRatio="none" viewBox="0 0 3 3" width="3">
          <circle cx="1.5" cy="1.5" fill="var(--fill-0, #10B981)" id="Ellipse" opacity="0.35" r="1.5" />
        </svg>
      </div>
      <div className="absolute left-[83%] size-[4px] top-[16%]" data-name="Ellipse">
        <svg className="absolute block inset-0 size-full" fill="none" height="4" preserveAspectRatio="none" viewBox="0 0 4 4" width="4">
          <circle cx="2" cy="2" fill="var(--fill-0, #06B6D4)" id="Ellipse" opacity="0.2" r="2" />
        </svg>
      </div>

      <Frame17 isStreaming={isStreaming} />
      <Frame18 statusText={statusText} />

      <p className="absolute left-1/2 -translate-x-1/2 bottom-[80px] md:bottom-[90px] font-['Montserrat:Bold',sans-serif] font-bold text-[#05b5d4] text-[24px] text-center tracking-[3px] whitespace-nowrap pointer-events-none z-10">
        THỰC HIỆN
      </p>

      <DateWeatherInfo dateStr={dateStr} />
      <LatestNews />

      {/* Main Interactive AI Agent Control Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-xl p-4 md:p-6">
          <div className="bg-[#090d16] rounded-2xl w-full max-w-4xl h-[85vh] flex flex-col overflow-hidden">
            
            {/* Modal Header */}
            <div className="px-6 py-4 flex items-center justify-between bg-slate-900/50">
              <div className="flex items-center gap-3">
                <div className="w-3 h-3 rounded-full bg-cyan-400 animate-pulse" />
                <h3 className="text-cyan-300 font-bold text-lg font-['Montserrat'] tracking-wide">
                  TRUNG TÂM ĐIỀU HÀNH MÌ TÔM AI
                </h3>
              </div>
              <button
                onClick={() => setIsModalOpen(false)}
                className="text-slate-400 hover:text-white p-1 rounded-lg hover:bg-slate-800 transition-colors"
              >
                <X className="w-6 h-6" />
              </button>
            </div>

            {/* Modal Chat / Execution Stream Timeline */}
            <div className="flex-1 overflow-y-auto p-6 space-y-4 font-sans text-sm">
              {messages.length === 0 ? (
                <div className="h-full flex flex-col items-center justify-center text-slate-500 gap-3">
                  <Sparkles className="w-12 h-12 text-cyan-500/40" />
                  <p className="text-center font-medium">Nhập câu lệnh hoặc chọn danh mục bên dưới để bắt đầu thực thi.</p>
                </div>
              ) : (
                messages.map((msg) => (
                  <div
                    key={msg.id}
                    className={`flex flex-col ${msg.sender === "user" ? "items-end" : "items-start"}`}
                  >
                    <div
                      className={`max-w-[85%] rounded-2xl px-5 py-3.5 ${
                        msg.sender === "user"
                          ? "bg-cyan-600/30 text-cyan-100 rounded-br-none"
                          : msg.isError
                          ? "bg-red-950/50 text-red-200 rounded-bl-none"
                          : "bg-slate-900 text-slate-200 rounded-bl-none"
                      }`}
                    >
                      <p className="whitespace-pre-wrap leading-relaxed">{msg.text || (isStreaming && msg.sender === "agent" ? "Đang suy nghĩ & thực thi..." : "")}</p>

                      {msg.image && (
                        <div className="mt-3 relative rounded-xl overflow-hidden group">
                          <img src={msg.image} alt="AI Generated" className="max-h-80 w-auto object-cover rounded-xl" />
                          <button
                            onClick={() => setPreviewMedia({ type: "image", src: msg.image! })}
                            className="absolute top-2 right-2 p-2 bg-black/60 rounded-lg text-white opacity-0 group-hover:opacity-100 transition-opacity"
                          >
                            <Maximize2 className="w-4 h-4" />
                          </button>
                        </div>
                      )}

                      {msg.video && (
                        <div className="mt-3 rounded-xl overflow-hidden">
                          <video src={msg.video} controls className="max-h-80 w-full rounded-xl" />
                        </div>
                      )}
                    </div>
                  </div>
                ))
              )}
              <div ref={messagesEndRef} />
            </div>

            {/* Quick Presets Bar inside Modal */}
            <div className="px-6 py-2 bg-slate-950/40 flex items-center gap-2 overflow-x-auto no-scrollbar">
              <span className="text-xs text-slate-400 font-semibold shrink-0">Gợi ý:</span>
              {Object.entries(CATEGORY_PRESETS).map(([key, item]) => (
                <button
                  key={key}
                  onClick={() => setPromptInput(item.prompt)}
                  className="px-3 py-1 rounded-full text-xs font-medium bg-slate-900 text-slate-300 hover:text-cyan-300 transition-all shrink-0 cursor-pointer"
                >
                  {item.label}
                </button>
              ))}
            </div>

            {/* Controls & Input Form */}
            <div className="p-6 bg-slate-900/80 space-y-3">
              {/* Settings row */}
              <div className="flex flex-wrap items-center justify-between gap-3 text-xs text-slate-400">
                <div className="flex items-center gap-3">
                  <label className="flex items-center gap-1.5 cursor-pointer hover:text-cyan-300">
                    <span className="font-semibold text-slate-300">Model:</span>
                    <select
                      value={selectedModel}
                      onChange={(e) => setSelectedModel(e.target.value)}
                      className="bg-slate-950 rounded-lg px-2.5 py-1 text-slate-200 outline-none cursor-pointer"
                    >
                      <option value="gemini-2.5-flash">Gemini 2.5 Flash</option>
                      <option value="claude-3-7-sonnet">Claude 3.7 Sonnet</option>
                      <option value="claude-3-5-sonnet">Claude 3.5 Sonnet</option>
                    </select>
                  </label>

                  <label className="flex items-center gap-1.5 cursor-pointer hover:text-cyan-300">
                    <span className="font-semibold text-slate-300">Đọc giọng nói (TTS):</span>
                    <select
                      value={ttsVoice}
                      onChange={(e) => setTtsVoice(e.target.value)}
                      className="bg-slate-950 rounded-lg px-2.5 py-1 text-slate-200 outline-none cursor-pointer"
                    >
                      <option value="vi-VN-HoaiMyNeural">Hoài Mỹ (Nữ)</option>
                      <option value="vi-VN-NamMinhNeural">Nam Minh (Nam)</option>
                      <option value="google">Google TTS</option>
                      <option value="none">Tắt đọc tiếng</option>
                    </select>
                  </label>
                </div>

                {selectedFiles.length > 0 && (
                  <span className="text-cyan-400 font-medium">
                    Đã đính kèm {selectedFiles.length} file
                  </span>
                )}
              </div>

              {/* Main Prompt Bar */}
              <div className="flex items-center gap-2 bg-slate-950 rounded-xl px-4 py-2.5 transition-colors">
                <input
                  type="file"
                  id="file-upload"
                  multiple
                  onChange={handleFileChange}
                  className="hidden"
                />
                <label
                  htmlFor="file-upload"
                  className="text-slate-400 hover:text-cyan-400 cursor-pointer p-1.5 rounded-lg hover:bg-slate-900 transition-colors"
                  title="Đính kèm tệp / ảnh"
                >
                  <Paperclip className="w-5 h-5" />
                </label>

                <input
                  type="text"
                  value={promptInput}
                  onChange={(e) => setPromptInput(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && !isStreaming && handleExecute()}
                  placeholder="Nhập yêu cầu hoặc câu lệnh thực thi hệ thống..."
                  className="flex-1 bg-transparent text-slate-100 placeholder-slate-500 outline-none text-sm font-medium"
                />

                <button
                  type="button"
                  onClick={toggleSpeechRecognition}
                  className={`p-2 rounded-lg transition-colors cursor-pointer ${
                    isListening ? "bg-red-600 text-white animate-pulse" : "text-slate-400 hover:text-cyan-400 hover:bg-slate-900"
                  }`}
                  title="Thu âm giọng nói"
                >
                  {isListening ? <MicOff className="w-5 h-5" /> : <Mic className="w-5 h-5" />}
                </button>

                <button
                  onClick={handleExecute}
                  disabled={isStreaming || (!promptInput.trim() && selectedFiles.length === 0)}
                  className="text-cyan-400 hover:text-cyan-300 disabled:text-slate-600 font-bold px-4 py-2 flex items-center gap-2 transition-all cursor-pointer disabled:cursor-not-allowed"
                >
                  {isStreaming ? (
                    <Loader2 className="w-5 h-5 animate-spin" />
                  ) : (
                    <>
                      <span>GỬI</span>
                      <Send className="w-4 h-4" />
                    </>
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Image / Video Lightbox Modal */}
      {previewMedia && (
        <div
          onClick={() => setPreviewMedia(null)}
          className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center p-8 cursor-pointer"
        >
          <div className="relative max-w-5xl max-h-[90vh]">
            <img src={previewMedia.src} alt="Preview" className="max-w-full max-h-[90vh] object-contain rounded-xl" />
          </div>
        </div>
      )}
    </div>
  );
}