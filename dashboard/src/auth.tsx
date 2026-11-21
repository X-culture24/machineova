import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { api, setUnauthorizedHandler, token, type LoginResult, type Me, type OtpChallenge } from "./api";

interface AuthState {
  me: Me | null;
  loading: boolean;
  /** The user, or a challenge when the account needs an emailed code. */
  signIn: (login: string, password: string) => Promise<Me | OtpChallenge>;
  verifyOtp: (otpToken: string, code: string) => Promise<Me>;
  signOut: () => void;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(() => token.get() !== null);

  const signOut = useCallback(() => {
    token.set(null);
    setMe(null);
  }, []);

  useEffect(() => {
    setUnauthorizedHandler(signOut);
    if (!token.get()) return;
    api
      .me()
      .then(setMe)
      .catch(signOut)
      .finally(() => setLoading(false));
  }, [signOut]);

  const start = useCallback((res: LoginResult) => {
    token.set(res.token);
    setMe(res.user);
    return res.user;
  }, []);

  const signIn = useCallback(async (login: string, password: string) => {
    const res = await api.login(login, password);
    if ("otp_required" in res) return res;
    return start(res);
  }, [start]);

  const verifyOtp = useCallback(async (otpToken: string, code: string) => start(await api.verifyOtp(otpToken, code)), [start]);

  return <AuthContext.Provider value={{ me, loading, signIn, verifyOtp, signOut }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth outside AuthProvider");
  return ctx;
}

export const isManager = (me: Me | null) => me?.role === "owner" || me?.role === "admin";
