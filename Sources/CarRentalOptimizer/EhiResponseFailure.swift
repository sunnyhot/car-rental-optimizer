/// Shared by the live WebKit bridge and JavaScriptCore regression tests.
func makeEhiResponseFailureScript() -> String {
    """
    const ehiResponseFailure = (response) => {
      const envelopes = [response, response?.data, response?.result, response?.data?.result, response?.data?.data]
        .filter(value => value && typeof value === 'object' && !Array.isArray(value));
      const expired = envelopes.find(value => Number(value.code) === 401 || Number(value.status) === 401);
      if (expired) return { statusKind: 'login-required', message: String(expired.message || expired.msg || '登录已过期，请重新登录。') };
      const failed = envelopes.find(value => value.isSuccess === false || value.success === false || Number(value.code) >= 400);
      if (!failed) return null;
      const message = String(failed.message || failed.msg || '平台接口返回异常');
      const statusKind = /验证码|安全验证/.test(message) ? 'captcha-required' : 'parse-failed';
      return { statusKind, message };
    };
    """
}
