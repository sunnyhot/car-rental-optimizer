func makeEhiQueryBudgetScript() -> String {
    """
    const ehiClock = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());
    const ehiDeadline = ehiClock() + Math.max(1, request.queryBudgetMilliseconds || 28000);
    let queryBudgetExpired = false;
    const remainingQueryBudget = () => Math.max(0, ehiDeadline - ehiClock());
    const withAPITimeout = async (operation, label) => {
      const remaining = remainingQueryBudget();
      if (remaining <= 0) { queryBudgetExpired = true; throw new Error('本次查询时限已到'); }
      let timer;
      try {
        return await Promise.race([
          Promise.resolve().then(() => {
            if (remainingQueryBudget() <= 0) { queryBudgetExpired = true; throw new Error('本次查询时限已到'); }
            return operation();
          }),
          new Promise((_, reject) => {
            timer = setTimeout(() => {
              if (remainingQueryBudget() <= 0) queryBudgetExpired = true;
              reject(new Error(label + ' 超时'));
            }, Math.min(apiTimeoutMs, remaining));
          })
        ]);
      } finally { clearTimeout(timer); }
    };
    const withEhiQueryBudget = async (operation) => {
      let timer;
      try {
        await Promise.race([
          operation(),
          new Promise(resolve => { timer = setTimeout(() => { queryBudgetExpired = true; resolve(); }, remainingQueryBudget()); })
        ]);
      } finally { clearTimeout(timer); }
    };
    const createEhiQueryQueue = (limit, onError = () => {}) => {
      const jobs = [];
      let active = 0, started = false, resolveIdle;
      const pump = () => {
        if (!started) return;
        if (remainingQueryBudget() <= 0) { queryBudgetExpired = true; jobs.length = 0; }
        while (active < limit && jobs.length && remainingQueryBudget() > 0) {
          const job = jobs.shift();
          active += 1;
          Promise.resolve().then(job).catch(onError).finally(() => { active -= 1; pump(); });
        }
        if (!jobs.length && !active && resolveIdle) { const resolve = resolveIdle; resolveIdle = null; resolve(); }
      };
      return {
        add: (job, priority = false) => { if (priority) jobs.unshift(job); else jobs.push(job); pump(); },
        addAll: (items, priority = false) => { if (priority) jobs.unshift(...items); else jobs.push(...items); pump(); },
        run: () => new Promise(resolve => { resolveIdle = resolve; started = true; pump(); })
      };
    };
    """
}
